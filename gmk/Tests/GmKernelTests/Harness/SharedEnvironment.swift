import Foundation
import GRDB
import XCTest

/// The ONE environment every case in this package shares: it hosts the kernel
/// IN THIS PROCESS against a freshly minted temporary root, hands out a
/// `DaemonClient` and a READ-ONLY database handle, and reaps both at the end.
///
/// The suite is the one writer. Cases still write only over the wire, through a
/// client with autostart off, so the socket path is what they exercise.
/// `Paths.root` is a `static let`, so `GM_FS_ROOT` is set before anything reads
/// it and this must be a process-scoped singleton.
final class SharedEnvironment: NSObject, XCTestObservation {

    /// Process-scoped, and `nonisolated(unsafe)` on purpose.
    ///
    /// The suite runs SERIALLY by construction: XCTest does not parallelise within
    /// a process, and this package chose XCTest over swift-testing because one
    /// shared append-only database cannot survive parallel cases. A lock here
    /// would imply concurrent access is supported; if cases ever do run
    /// concurrently, the database is the problem, not this reference.
    nonisolated(unsafe) static let shared = SharedEnvironment()

    private(set) var root: URL!
    private(set) var client: DaemonClient!
    /// Why the in-process kernel did not boot, for the skip message.
    private(set) var bootFailure: String?
    private var kernel: KernelServices?
    private var started = false

    /// Registers the environment and boots the kernel once if needed.
    ///
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

    /// Creates a temporary root, boots the kernel in-process on it, and opens a wire client.
    ///
    /// Precondition: `started` is true.
    private func boot() {
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gmk-\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = Self.stageKernel(into: root)

        // The socket path is what has to fit in 104 bytes. Assert it here
        // rather than letting the bind fail opaquely later.
        let socketPath = root.appendingPathComponent("daemon.sock", isDirectory: false).path
        precondition(
            socketPath.utf8.count < 104,
            "socket path \(socketPath.utf8.count) bytes — sun_path is 104 on macOS; shorten the run id"
        )

        // xctest's Bundle.main bakes no GMFSRoot, so this is the arm Paths.root resolves.
        setenv("GM_FS_ROOT", root.path, 1)
        precondition(
            Paths.root.standardizedFileURL.path == root.standardizedFileURL.path,
            "Paths.root was read before the harness set GM_FS_ROOT: \(Paths.root.path)"
        )

        do {
            let outcome = try KernelOwnership.acquire()
            switch consume outcome {
            case .acquired(let token):
                kernel = try KernelServices.bootWriter(consume token)
            case .heldBy(let holder):
                bootFailure = "the run root's lock is held by pid \(holder.pid)"
            }
        } catch {
            bootFailure = String(describing: error)
        }

        client = DaemonClient(socketPath: socketPath, autostart: false)

        // NWListener binds asynchronously; the first case must not race it.
        guard kernel != nil else { return }
        for _ in 0..<50 where !isAvailable {
            usleep(100_000)
        }
    }

    /// True when a real kernel is reachable.
    ///
    /// Cases skip rather than fail when it is not: a machine that has never built the kernel should report "not built",
    /// not a wall of assertion failures that look like regressions.
    var isAvailable: Bool {
        guard let client else { return false }
        return
            (try? client.request(
                type: .ping,
                payload: PingRequest(),
                responseType: PingResponse.self
            )) != nil
    }

    /// Round-trip one verb over the wire.
    ///
    /// The suite's ONLY write path — every mutation goes over the wire exactly as a real client's would, which is what
    /// makes "public interfaces" literally true here rather than aspirational.
    ///
    /// - Parameters:
    ///   - type: The message type to send.
    ///   - payload: The request payload.
    ///   - responseType: The expected response type.
    /// - Returns: The response deserialized from the server.
    /// - Throws: `XCTSkip` if no kernel is available, or a decode error if parsing fails.
    @discardableResult
    func send<Req: Codable & Sendable, Resp: Codable & Sendable>(
        _ type: MessageType,
        _ payload: Req,
        _ responseType: Resp.Type
    ) throws -> Resp {
        guard let client else {
            throw XCTSkip("no kernel")
        }
        return try client.request(type: type, payload: payload, responseType: responseType)
    }

    func testBundleDidFinish(_: Bundle) {
        shutdown()
    }

    /// Shuts down the kernel and cleans up the temporary root.
    ///
    /// The hosted teardown, never the SHUTDOWN verb: this process is the host.
    /// Failures are silently ignored; the suite must not fail on cleanup.
    private func shutdown() {
        client?.close()
        kernel?.shutdown()
        kernel = nil
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
    ///
    /// - Returns: A read-only database queue connected to `gm.db`.
    /// - Throws: An error if the database cannot be opened.
    func readOnlyDatabase() throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(
            path: root.appendingPathComponent("gm.db", isDirectory: false).path,
            configuration: config
        )
    }

    // MARK: - Staging the binary under test

    /// Copy the kernel binary into the run root for cases that run it as the pen, and return the copy.
    ///
    /// `GM_TEST_KERNEL_BIN` first, else the app bundle beside this test bundle in
    /// BUILT_PRODUCTS_DIR. Never `~/gmfs/bin/gm_kernel`: that would test the last
    /// RELEASE instead of the working tree. The COPY is what runs, so no
    /// Info.plist sits beside it and the harness's GM_FS_ROOT wins over the baked root.
    /// It is a client of the in-process kernel, never a writer.
    ///
    /// - Parameter root: The run root directory where the kernel is staged.
    /// - Returns: The path to the copied kernel, or nil if the source is not found.
    private static func stageKernel(into root: URL) -> URL? {
        let env = ProcessInfo.processInfo.environment["GM_TEST_KERNEL_BIN"]
        let source =
            env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? Bundle(for: SharedEnvironment.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("gm_kernel.app/Contents/MacOS/gm_kernel")
        guard FileManager.default.isExecutableFile(atPath: source.path) else { return nil }
        let copy = root.appendingPathComponent("gm_kernel")
        return (try? FileManager.default.copyItem(at: source, to: copy)) == nil ? nil : copy
    }
}

/// Base class for cases that need the booted kernel.
///
/// Skips the whole class when the in-process kernel did not boot, with the
/// reason. A suite that cannot boot the thing it tests should say so once, not
/// fail every assertion in turn.
class KernelBackedTestCase: XCTestCase {

    var env: SharedEnvironment { SharedEnvironment.shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        SharedEnvironment.bootIfNeeded()
        try XCTSkipUnless(
            SharedEnvironment.shared.isAvailable,
            "in-process kernel failed to boot: \(SharedEnvironment.shared.bootFailure ?? "not reachable over the wire")"
        )
    }
}
