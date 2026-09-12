import XCTest
@testable import GMCCDaemonKit

/// The SessionStart env contract: emitted line shape, PATH dedup idempotence,
/// the shim's resolution rule, and the env-vs-db consistency findings.
///
/// EVERY root in this file is INJECTED. Nothing here resolves a live runtime
/// path, and nothing reads the process environment, because both make a test's
/// verdict depend on whether the runtime happens to be installed on the machine
/// running it. `testCheckFlagsGmFsRootMismatch` is the cautionary tale:
/// its mismatch assertion used to be gated on `GM_FS_ROOT` being present in
/// the real environment, so on any machine without the runtime installed the
/// test skipped its only real assertion and passed on the trivial half.
final class EnvContractTests: XCTestCase {

    /// A root that exists nowhere near the live runtime. Stable per test case so
    /// the emitted/asserted values agree, and never created on disk — these
    /// tests only ever compare strings.
    private let fakeRoot = URL(
        fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
    ).appendingPathComponent("gm-env-contract-fake-root", isDirectory: true)

    private var fakeBin: URL { fakeRoot.appendingPathComponent("bin", isDirectory: true) }

    /// The claim side of the env/db check, stated rather than inherited. ONE
    /// var now, where this used to build two.
    private func claimEnv(gmFsRoot: String?) -> [String: String] {
        guard let gmFsRoot else { return [:] }
        return ["GM_FS_ROOT": gmFsRoot]
    }

    /// A response with one root and everything else blank — these tests are
    /// about the root comparison and nothing else.
    private func response(gmFsRoot: String) -> PathsGetResponse {
        PathsGetResponse(
            gmFsRoot: gmFsRoot, dbPath: "", socketPath: "", backupsRoot: "",
            projectsRoot: "", kbiteRoot: "", kbiteOpenRoot: "", kbiteDigestedRoot: "")
    }

    func testEmittedLinesAreEnvFileShaped() {
        let lines = GmEnvironment.emit(
            pluginRoot: "/plugins/gmcc", inheritedPath: "/usr/bin:/bin",
            env: claimEnv(gmFsRoot: "/fake/gmfs"), bin: fakeBin)
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            // export, not a bare assignment: a bare assignment is a shell
            // variable no child process inherits.
            XCTAssertTrue(line.range(of: #"^export [A-Z_]+='"#, options: .regularExpression) != nil,
                          "not an export KEY='VALUE' line: \(line)")
            XCTAssertTrue(line.hasSuffix("'"), "value not closed-quoted: \(line)")
            XCTAssertFalse(line.contains("\n"))
        }
        XCTAssertTrue(lines.contains("export GM_BOOTED='1'"))
        XCTAssertTrue(lines.contains("export GM_PLUGIN_ROOT='/plugins/gmcc'"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("export GM_FS_ROOT='") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("export PATH='") })
    }

    func testDbGmFsRootWinsWhenProvided() {
        let lines = GmEnvironment.emit(
            pluginRoot: "/p", inheritedPath: "", dbFsRoot: "/db/gmfs",
            env: claimEnv(gmFsRoot: "/env/gmfs"), bin: fakeBin)
        XCTAssertTrue(lines.contains("export GM_FS_ROOT='/db/gmfs'"))
    }

    func testPathValueIsIdempotentAndLeadsWithRuntimeBin() {
        let mine = fakeBin.path
        let once = GmEnvironment.pathValue(current: "/usr/bin:/bin", bin: fakeBin)
        XCTAssertTrue(once.hasPrefix("\(mine):"))
        let twice = GmEnvironment.pathValue(current: once, bin: fakeBin)
        XCTAssertEqual(once, twice, "re-emission must not stack PATH entries")
    }

    func testPathLineIsFullyResolvedLiteral() {
        let lines = GmEnvironment.emit(
            pluginRoot: "/p", inheritedPath: "/usr/bin",
            env: claimEnv(gmFsRoot: "/fake/gmfs"), bin: fakeBin)
        let path = lines.first { $0.hasPrefix("export PATH='") }!
        // Single-quoted values never expand — a $PATH reference would ship as
        // four literal characters and corrupt the session's PATH.
        XCTAssertFalse(path.contains("$"))
    }

    func testShellQuoteSurvivesSpacesAndQuotes() {
        XCTAssertEqual(GmEnvironment.shellQuote("/a/b"), "'/a/b'")
        XCTAssertEqual(GmEnvironment.shellQuote("/VMware Fusion.app"),
                       "'/VMware Fusion.app'")
        XCTAssertEqual(GmEnvironment.shellQuote("it's"), #"'it'\''s'"#)
    }

    /// The regression this shape exists for: a PATH component with a space
    /// (macOS ships `/Applications/VMware Fusion.app/Contents/Public` via
    /// path_helper) used to truncate the assignment, leaving PATH unset and
    /// printing a shell error before every Bash command in the session.
    func testEnvFilePreambleRoundTripsThroughRealShell() throws {
        let spacey = "/Applications/VMware Fusion.app/Contents/Public"
        let lines = GmEnvironment.emit(
            pluginRoot: "/plugins/gmcc", inheritedPath: "/usr/bin:\(spacey):/bin",
            env: claimEnv(gmFsRoot: "/fake/gmfs"), bin: fakeBin)
        let script = lines.joined(separator: "\n")
            + "\nprintf '%s\\n' \"$GM_BOOTED\" \"$PATH\"\n"
            + "/bin/sh -c 'printf \"child=%s\\n\" \"$GM_PLUGIN_ROOT\"'\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        XCTAssertEqual(stderr, "", "the preamble must be silent — it runs before every Bash command")
        XCTAssertEqual(process.terminationStatus, 0)
        let printed = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(printed.first, "1", "GM_BOOTED did not survive the preamble")
        XCTAssertTrue(printed.count > 1 && printed[1].contains(spacey),
                      "the spaced PATH component was lost: \(stdout)")
        XCTAssertTrue(printed[1].hasPrefix("\(fakeBin.path):"),
                      "PATH assignment did not take effect: \(stdout)")
        XCTAssertTrue(stdout.contains("child=/plugins/gmcc"),
                      "values reached the shell but not child processes: \(stdout)")
    }

    func testShimResolvesTheFsRootAtCallTime() {
        XCTAssertTrue(GmEnvironment.shimScript
            .contains(#"exec "${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook" "$@""#))
        XCTAssertTrue(GmEnvironment.shimScript.hasPrefix("#!/bin/sh"))
    }

    /// The claim is an INPUT, not ambient state. This assertion is now
    /// UNCONDITIONAL: it runs identically on a machine with the runtime
    /// installed and on one without.
    func testCheckFlagsFsRootMismatch() {
        let findings = GmEnvironment.check(
            response(gmFsRoot: "/definitely/not/the/env/value"),
            env: claimEnv(gmFsRoot: "/some/other/gmfs"))
        XCTAssertTrue(findings.contains { $0.code == "gmfs_root_mismatch" },
                      "a disagreeing claim must produce the finding: \(findings.map(\.code))")
    }

    func testCheckPassesWhenTheClaimAgrees() {
        XCTAssertTrue(
            GmEnvironment.check(
                response(gmFsRoot: "/some/other/gmfs"),
                env: claimEnv(gmFsRoot: "/some/other/gmfs")
            ).isEmpty)
    }

    /// `..` traversal and a trailing slash are the same root, not a mismatch —
    /// the check standardizes both sides before comparing, so a cosmetically
    /// different spelling must not raise a false alarm on every boot.
    func testCheckStandardizesBeforeComparing() {
        XCTAssertTrue(
            GmEnvironment.check(
                response(gmFsRoot: "/Users/x/gmfs"),
                env: claimEnv(gmFsRoot: "/Users/x/other/../gmfs/")
            ).isEmpty)
    }

    /// An absent claim is not a mismatch — but it is also not a pass for the
    /// mismatch case, which is what the old two-var shape conflated.
    func testAbsentClaimProducesNoFinding() {
        XCTAssertTrue(GmEnvironment.check(response(gmFsRoot: "/anything"), env: [:]).isEmpty)
        // An empty claim is treated as absent, not as an empty path that
        // disagrees with everything.
        XCTAssertTrue(
            GmEnvironment.check(
                response(gmFsRoot: "/anything"), env: ["GM_FS_ROOT": ""]
            ).isEmpty)
    }

    /// The fallback resolves from the INJECTED env, so this asserts the rule
    /// rather than the machine.
    func testFallbackGmFsRootPrefersTheEnvClaim() {
        XCTAssertEqual(
            GmEnvironment.fallbackFsRoot(env: ["GM_FS_ROOT": "/claimed/gmfs"]).path,
            "/claimed/gmfs")
        // An empty claim is treated as absent, not as an empty path.
        XCTAssertTrue(
            GmEnvironment.fallbackFsRoot(env: ["GM_FS_ROOT": ""])
                .path.hasSuffix("gmfs"))
    }
}
