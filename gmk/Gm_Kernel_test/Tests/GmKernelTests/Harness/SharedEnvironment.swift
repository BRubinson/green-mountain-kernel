import Foundation
import GRDB
import GmDaemonSdk
import XCTest

/// The ONE environment every case in this package shares.
///
/// Boots a real `gm_kernel` against a freshly minted temporary root, hands out
/// a `DaemonClient` and a READ-ONLY database handle, and reaps both when the
/// bundle finishes.
///
/// ## One root per process — not a simplification, a constraint
///
/// `Paths.root` is a `static let`. Whatever root the process resolves first is
/// the root it has forever. A per-suite or per-test environment CANNOT take
/// effect, and code written as though it could fails silently against the first
/// root that happened to win. That is why this is a process-scoped singleton
/// rather than a fixture someone can instantiate twice.
///
/// ## Isolation by construction
///
/// Nothing here calls `Paths.*` to discover a path. The root is minted under
/// `NSTemporaryDirectory()` and every path beneath it is string-appended, so
/// there is no expression in this file that can resolve the installed runtime
/// even by mistake. `GM_FS_ROOT` is WRITTEN into the spawned child's
/// environment; it is never read to decide anything here.
///
/// ## Why the run id is short
///
/// The kernel binds a unix socket at `<root>/daemon.sock`, and `sun_path` is
/// **104 bytes** on macOS. A timestamp-and-pid identifier plus a long home
/// directory overruns that, and the failure is not a clear error — it is a
/// listener that never binds and a client that times out looking healthy.
/// Six hex characters under the system temp directory leaves ample headroom.
final class SharedEnvironment: NSObject, XCTestObservation {

    /// Process-scoped, and `nonisolated(unsafe)` on purpose.
    ///
    /// Swift 6 is right that this is shared mutable state; what it cannot see is
    /// that the suite runs SERIALLY by construction. XCTest does not parallelise
    /// within a process, and this package chose XCTest over swift-testing
    /// precisely because a single shared append-only database cannot survive
    /// parallel cases. Adding a lock here would suggest concurrent access is
    /// expected and supported. It is neither — if cases ever do run
    /// concurrently, the database is the problem, not this reference.
    nonisolated(unsafe) static let shared = SharedEnvironment()

    private(set) var root: URL!
    private(set) var client: DaemonClient!
    private var kernelBinary: URL!
    private var started = false

    /// Registered from `XCTestObservationCenter` the first time any case asks
    /// for the environment. Registration is idempotent; boot happens once.
    static func bootIfNeeded() {
        let env = SharedEnvironment.shared
        guard !env.started else { return }
        env.started = true
        XCTestObservationCenter.shared.addTestObserver(env)
        env.boot()
    }

    // MARK: - Lifecycle

    private func boot() {
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gmk-\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true)

        kernelBinary = Self.locateKernelBinary()

        // The socket path is what has to fit in 104 bytes. Assert it here
        // rather than letting the bind fail opaquely later.
        let socketPath = root.appendingPathComponent("daemon.sock", isDirectory: false).path
        precondition(
            socketPath.utf8.count < 104,
            "socket path \(socketPath.utf8.count) bytes — sun_path is 104 on macOS; shorten the run id")

        guard let kernelBinary else { return }

        // `autostart: true` makes the client spawn the kernel on first use. The
        // spawn injects GM_FS_ROOT explicitly (see DaemonClient.spawnDaemon), so
        // the child lands on OUR root rather than inheriting whatever this
        // process was launched with.
        setenv("GM_FS_ROOT", root.path, 1)
        client = DaemonClient(
            socketPath: socketPath,
            daemonBinaryPath: kernelBinary.path,
            autostart: true)
    }

    /// True when a real kernel is reachable. Cases skip rather than fail when it
    /// is not: a machine that has never built the kernel should report "not
    /// built", not a wall of assertion failures that look like regressions.
    var isAvailable: Bool {
        guard let client else { return false }
        return
            (try? client.request(
                type: .ping, payload: PingRequest(), responseType: PingResponse.self)) != nil
    }

    /// Round-trip one verb. The suite's ONLY write path — every mutation goes
    /// over the wire exactly as a real client's would, which is what makes
    /// "public interfaces" literally true here rather than aspirational.
    @discardableResult
    func send<Req: Codable & Sendable, Resp: Codable & Sendable>(
        _ type: MessageType, _ payload: Req, _ responseType: Resp.Type
    ) throws -> Resp {
        guard let client else {
            throw XCTSkip("no kernel")
        }
        return try client.request(type: type, payload: payload, responseType: responseType)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        shutdown()
    }

    private func shutdown() {
        if let client {
            _ = try? client.request(
                type: .shutdown, payload: ShutdownRequest(), responseType: ShutdownResponse.self)
            client.close()
        }
        // Best-effort: the kernel may already be gone, and a failure to tidy a
        // temp directory must never fail a suite.
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Read-only database access

    /// A READ-ONLY handle on the booted kernel's database.
    ///
    /// Read-only is the correctness rule, not a precaution. The kernel holds the
    /// `flock` and owns this file as sole writer; a writable handle here would be
    /// the second writer the ownership token exists to forbid, opened by the very
    /// suite meant to defend that property. Assertions read; the wire writes.
    func readOnlyDatabase() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(
            path: root.appendingPathComponent("gm.db", isDirectory: false).path,
            configuration: config)
    }

    // MARK: - Locating the binary under test

    /// Find the `gm_kernel` this suite should exercise.
    ///
    /// Order:
    ///   1. `GM_TEST_KERNEL_BIN` — what CI and `run_kernel_tests.sh` set.
    ///   2. the repo's own `.build` products, so a developer who just ran
    ///      `swift build` can run the suite with no extra ceremony.
    ///
    /// Deliberately NEVER `~/gmfs/bin/gm_kernel`. Falling back to the installed
    /// runtime would mean the suite silently tested the LAST RELEASE instead of
    /// the working tree — green for code that does not exist here.
    private static func locateKernelBinary() -> URL? {
        if let explicit = ProcessInfo.processInfo.environment["GM_TEST_KERNEL_BIN"],
            !explicit.isEmpty,
            FileManager.default.isExecutableFile(atPath: explicit)
        {
            return URL(fileURLWithPath: explicit)
        }
        let repo = repoRoot()
        for config in ["debug", "release"] {
            let candidate =
                repo
                .appendingPathComponent("gmk/gmKernel/.build/\(config)/gm_kernel")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// The repository root, from this file's own location.
    ///
    /// `#filePath` rather than a directory walk from the working directory:
    /// `swift test` can be invoked from anywhere, and a relative walk silently
    /// resolves against whatever shell happened to launch it.
    static func repoRoot() -> URL {
        // …/gmk/Gm_Kernel_test/Tests/GmKernelTests/Harness/ThisFile.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }
}

/// Base class for cases that need the booted kernel.
///
/// Skips the whole class when no kernel binary is present, with a message that
/// says what to do about it. A suite that cannot find the thing it tests should
/// say so once, not fail every assertion in turn.
class KernelBackedTestCase: XCTestCase {

    var env: SharedEnvironment { SharedEnvironment.shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        SharedEnvironment.bootIfNeeded()
        try XCTSkipUnless(
            SharedEnvironment.shared.isAvailable,
            "no gm_kernel to test — build it first: "
                + "swift build --package-path gmk/gmKernel  (or set GM_TEST_KERNEL_BIN)")
    }
}
