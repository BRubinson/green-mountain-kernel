import XCTest

/// The contract that makes single-writer a TYPE rather than a habit.
///
/// The architecture for the kernel collapse was chosen over its closest rival
/// specifically because opening the database would become impossible without
/// holding the lock — `KernelOwnership.Token` is `~Copyable` with a `fileprivate`
/// initialiser, and `KernelWriter.start` consumes one. That argument is only
/// worth anything while `KernelWriter` really is the ONLY site that constructs a
/// `Store`, and nothing in the compiler enforces "only". This file does.
///
/// It reads FILES rather than calling symbols, which is why it lives in
/// gmToolchain: `Store(path:)` is legal everywhere inside `GmDaemon`, so no
/// access-control rule can express the constraint. A source scan can.
final class KernelHostContractTests: XCTestCase {

    private var gmk: URL { RepoRoot.gmkRoot() }

    private func swiftSources(under relative: String) throws -> [URL] {
        let root = gmk.appendingPathComponent(relative, isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { !$0.path.contains("/.build/") }
    }

    /// `KernelWriter.swift` is the ONLY file that may construct a `Store`.
    ///
    /// Exempt: `Store.swift` itself (it declares the initialiser), and the test
    /// suites, which build throwaway databases in temp directories and never
    /// touch the real one — `LiveRuntimeIsolationTests` is what keeps that true.
    func testKernelWriterIsTheOnlyStoreConstructionSite() throws {
        var offenders: [String] = []
        for dir in ["gmDaemon/Sources", "gmDaemonSdk/Sources", "gmMcp/Sources", "gmKernel/Sources"] {
            for file in try swiftSources(under: dir) {
                let name = file.lastPathComponent
                if name == "KernelWriter.swift" || name == "Store.swift" { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                    if line.contains("Store(path:") {
                        offenders.append("\(name):\(i + 1): \(trimmed)")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            a second Store construction site appeared. Opening the database must \
            go through KernelWriter.start, which consumes a KernelOwnership.Token \
            — the token is the only thing standing between two app copies and two \
            writers on an append-only history:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The token's initialiser stays unreachable.
    ///
    /// A `Token` anyone can construct is a lock anyone can claim to hold, which
    /// turns the whole guarantee back into a comment.
    func testOwnershipTokenCannotBeConstructedElsewhere() throws {
        let source = try String(
            contentsOf: gmk.appendingPathComponent(
                "gmDaemon/Sources/GmKernelHost/KernelOwnership.swift"),
            encoding: .utf8)
        XCTAssertTrue(
            source.contains("public struct Token: ~Copyable"),
            "Token stopped being ~Copyable — it could then be duplicated into a second writer")
        XCTAssertTrue(
            source.contains("fileprivate init(fd:"),
            "Token's initialiser is no longer fileprivate — anything could mint one")

        // And nothing outside that file names it as a constructor.
        var offenders: [String] = []
        for dir in ["gmDaemon/Sources", "gmKernel/Sources"] {
            for file in try swiftSources(under: dir)
            where file.lastPathComponent != "KernelOwnership.swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("Token(fd:") {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "a Token was constructed outside KernelOwnership: \(offenders)")
    }

    /// The runtime-state filenames are NOT renamed.
    ///
    /// The sharpest easy mistake in this area: a kernel locking `kernel.pid`
    /// beside an older one holding `daemon.pid` takes a DIFFERENT LOCK, and both
    /// proceed to write the same database believing each is alone. The word
    /// "daemon" in a filename costs nothing; a second writer costs the history.
    func testRuntimeStateFilenamesAreUnchanged() throws {
        let paths = try String(
            contentsOf: gmk.appendingPathComponent(
                "gmDaemonSdk/Sources/GmDaemonSdk/Paths.swift"),
            encoding: .utf8)
        XCTAssertTrue(paths.contains("\"daemon.pid\""), "the pidfile was renamed — see the doc comment")
        XCTAssertTrue(paths.contains("\"daemon.sock\""), "the socket was renamed — see the doc comment")
    }

    /// The app target must not reach persistence directly.
    ///
    /// The app hosts the writer, so GRDB is legitimately in its link closure now
    /// — but reads still go through the same verbs the socket handlers call, so
    /// there is exactly one implementation per verb. A direct `DatabaseQueue` in
    /// a view model would be a second code path that `VerbRegistryTests` cannot
    /// see.
    func testAppTargetDoesNotReachPersistenceDirectly() throws {
        var offenders: [String] = []
        let appRoot = gmk.appendingPathComponent("gmVibes", isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        else { return XCTFail("cannot enumerate the app target") }
        for case let file as URL in walker where file.pathExtension == "swift" {
            if file.path.contains("/build/") { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in ["import GRDB", "DatabaseQueue"] where text.contains(needle) {
                offenders.append("\(file.lastPathComponent): \(needle)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            the app target reaches persistence directly. In-process callers must \
            go through the public Store verbs, which are what the socket handlers \
            call — one implementation per verb, or VerbRegistryTests stops meaning \
            anything:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
