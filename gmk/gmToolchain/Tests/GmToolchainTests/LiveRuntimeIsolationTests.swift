import XCTest
@testable import GmDaemonSdk

/// The suite-wide live-runtime guard: this test suite must be provably unable
/// to read or write the installed runtime.
///
/// The reason it is a SOURCE SCAN rather than a runtime check: a test that
/// resolves `Paths.root` does not fail — it quietly succeeds against whatever
/// the ambient machine happens to have installed. There is nothing to observe
/// at runtime, so the only place to catch it is in the text. `EnvContractTests`
/// is the cautionary case: an assertion gated on a real env var stopped
/// asserting anything on a machine without the runtime installed, and stayed
/// green for it.
///
/// KEEP THE ALLOWLISTS EMPTY. Every root a test needs is injectable — inject
/// it. An exemption here is an exemption from the isolation guarantee itself.
///
/// SCOPE: every test target in `gmk/`, not just this package's. A guard that
/// covers one fifth of the suite is a guard that reports "no violations" while
/// four other packages read the live runtime freely.
final class LiveRuntimeIsolationTests: XCTestCase {

    /// EVERY package's Tests/ tree, located by marker via the shared helper.
    private func testSources() throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for name in RepoRoot.sourcePackages + ["gmToolchain"] {
            let root = RepoRoot.package(name)
                .appendingPathComponent("Tests", isDirectory: true)
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            while let url = walker.nextObject() as? URL {
                if url.pathExtension == "swift" { out.append(url) }
            }
        }
        // A loud failure beats a vacuous pass: if the walk stops finding the
        // suite, this test would otherwise report "no violations" forever.
        XCTAssertGreaterThan(out.count, 40,
                             "test tree walk looks broken — found \(out.count) files")
        return out
    }

    private func name(_ url: URL) -> String { url.lastPathComponent }

    /// Files whose TEXT necessarily spells the tokens these tests ban.
    ///
    /// This file's own banned-token list is the obvious case. The less obvious
    /// one is `RetiredNameContractTests`: it is the sibling guard, and its
    /// exemption tables have to NAME the symbols and paths they exempt. Two
    /// source-scanning guards will always flag each other unless each is told
    /// the other is prose, not code.
    private let proseNotCode: Set<String> = [
        "LiveRuntimeIsolationTests.swift",
        "RetiredNameContractTests.swift",
    ]

    private func scannable() throws -> [URL] {
        try testSources().filter { !proseNotCode.contains(name($0)) }
    }

    /// `Paths.<member>` resolves against the real `$GM_FS_ROOT` / `$HOME`, so
    /// any test naming one is asserting about the machine it runs on.
    func testNoTestResolvesTheLiveRuntimeRoot() throws {
        let banned = [
            "Paths.root", "Paths.bin", "Paths.db", "Paths.backups",
            "Paths.socket", "Paths.pidfile", "Paths.log",
            "Paths.binKernel", "Paths.binDaemon", "Paths.binMcp", "Paths.binHook",
            "Paths.contentRoot", "Paths.projectsRoot", "Paths.kbitesRoot",
            "Paths.versionStamp",
            "Paths.ensureRuntimeDirs",
        ]
        var violations: [String] = []
        for file in try scannable() {
            let body = try String(contentsOf: file, encoding: .utf8)
            for token in banned where body.contains(token) {
                violations.append("\(name(file)): \(token)")
            }
        }
        XCTAssertEqual(violations, [], """
            these tests resolve the installed runtime instead of an injected \
            root. Every Paths member is machine state; pass the root in. \
            Violations: \(violations)
            """)
    }

    /// The home directory is the other door to the live runtime.
    func testNoTestResolvesTheHomeDirectory() throws {
        let banned = ["homeDirectoryForCurrentUser", "NSHomeDirectory"]
        var violations: [String] = []
        for file in try scannable() {
            let body = try String(contentsOf: file, encoding: .utf8)
            for token in banned where body.contains(token) {
                violations.append("\(name(file)): \(token)")
            }
        }
        XCTAssertEqual(violations, [],
                       "tests must build paths under a temp root, not under $HOME: \(violations)")
    }

    /// A test may read an env var only to SKIP itself. Reading one to decide
    /// what to assert is how an assertion silently stops running.
    ///
    /// The two db-copy tests are the legitimate shape: both skip when the var
    /// is absent and both operate on a copy the caller made.
    func testEnvVarReadsAreSkipGatesOnly() throws {
        let allowed: Set<String> = [
            // Skip-gates: `GM_TEST_DB_COPY` names a COPY supplied by the caller.
            "LiveMigrationSmokeTests.swift",
            "MigrationTests.swift",
        ]
        var violations: [String] = []
        for file in try scannable() where !allowed.contains(name(file)) {
            let body = try String(contentsOf: file, encoding: .utf8)
            if body.contains("ProcessInfo.processInfo.environment")
                || body.contains("getenv(") {
                violations.append(name(file))
            }
        }
        XCTAssertEqual(violations, [], """
            these tests read the process environment. Inject the value instead \
            — an assertion conditioned on ambient env is an assertion that \
            stops running on a machine without the runtime installed. \
            Violations: \(violations)
            """)
    }

    /// Every env var the two allowed files read must be a `GM_TEST_*` name, so
    /// a test can never be steered by a var the real runtime also sets.
    func testDbCopyGatesUseTestOnlyEnvNames() throws {
        for file in try testSources()
        where ["LiveMigrationSmokeTests.swift", "MigrationTests.swift"].contains(name(file)) {
            let body = try String(contentsOf: file, encoding: .utf8)
            let reads = body.ranges(of: #/environment\["(?<key>[A-Z_]+)"\]/#)
                .map { String(body[$0]) }
            for read in reads {
                XCTAssertTrue(read.contains("GM_TEST_"), """
                    \(name(file)) reads \(read) — db-copy gates must use a \
                    GM_TEST_* name the production runtime never sets
                    """)
            }
        }
    }
}
