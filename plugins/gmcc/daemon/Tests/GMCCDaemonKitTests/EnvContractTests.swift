import XCTest
@testable import GMCCDaemonKit

/// The SessionStart env contract: emitted line shape, PATH dedup idempotence,
/// the shim's resolution rule, and the env-vs-db consistency findings.
final class EnvContractTests: XCTestCase {

    func testEmittedLinesAreEnvFileShaped() {
        let lines = GmccEnvironment.emit(
            pluginRoot: "/plugins/gmcc", inheritedPath: "/usr/bin:/bin")
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            // export, not a bare assignment: a bare assignment is a shell
            // variable no child process inherits.
            XCTAssertTrue(line.range(of: #"^export [A-Z_]+='"#, options: .regularExpression) != nil,
                          "not an export KEY='VALUE' line: \(line)")
            XCTAssertTrue(line.hasSuffix("'"), "value not closed-quoted: \(line)")
            XCTAssertFalse(line.contains("\n"))
        }
        XCTAssertTrue(lines.contains("export GMCC_BOOTED='1'"))
        XCTAssertTrue(lines.contains("export GMCC_PLUGIN_ROOT='/plugins/gmcc'"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("export GMCC_CKFS_ROOT='") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("export PATH='") })
    }

    func testDbCkfsRootWinsWhenProvided() {
        let lines = GmccEnvironment.emit(
            pluginRoot: "/p", inheritedPath: "", dbCkfsRoot: "/db/ckfs")
        XCTAssertTrue(lines.contains("export GMCC_CKFS_ROOT='/db/ckfs'"))
    }

    func testPathValueIsIdempotentAndLeadsWithRuntimeBin() {
        let mine = Paths.bin.path
        let once = GmccEnvironment.pathValue(current: "/usr/bin:/bin")
        XCTAssertTrue(once.hasPrefix("\(mine):"))
        let twice = GmccEnvironment.pathValue(current: once)
        XCTAssertEqual(once, twice, "re-emission must not stack PATH entries")
    }

    func testPathLineIsFullyResolvedLiteral() {
        let lines = GmccEnvironment.emit(pluginRoot: "/p", inheritedPath: "/usr/bin")
        let path = lines.first { $0.hasPrefix("export PATH='") }!
        // Single-quoted values never expand — a $PATH reference would ship as
        // four literal characters and corrupt the session's PATH.
        XCTAssertFalse(path.contains("$"))
    }

    func testShellQuoteSurvivesSpacesAndQuotes() {
        XCTAssertEqual(GmccEnvironment.shellQuote("/a/b"), "'/a/b'")
        XCTAssertEqual(GmccEnvironment.shellQuote("/VMware Fusion.app"),
                       "'/VMware Fusion.app'")
        XCTAssertEqual(GmccEnvironment.shellQuote("it's"), #"'it'\''s'"#)
    }

    /// The regression this shape exists for: a PATH component with a space
    /// (macOS ships `/Applications/VMware Fusion.app/Contents/Public` via
    /// path_helper) used to truncate the assignment, leaving PATH unset and
    /// printing a shell error before every Bash command in the session.
    func testEnvFilePreambleRoundTripsThroughRealShell() throws {
        let spacey = "/Applications/VMware Fusion.app/Contents/Public"
        let lines = GmccEnvironment.emit(
            pluginRoot: "/plugins/gmcc", inheritedPath: "/usr/bin:\(spacey):/bin")
        let script = lines.joined(separator: "\n")
            + "\nprintf '%s\\n' \"$GMCC_BOOTED\" \"$PATH\"\n"
            + "/bin/sh -c 'printf \"child=%s\\n\" \"$GMCC_PLUGIN_ROOT\"'\n"

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
        XCTAssertEqual(printed.first, "1", "GMCC_BOOTED did not survive the preamble")
        XCTAssertTrue(printed.count > 1 && printed[1].contains(spacey),
                      "the spaced PATH component was lost: \(stdout)")
        XCTAssertTrue(printed[1].hasPrefix("\(Paths.bin.path):"),
                      "PATH assignment did not take effect: \(stdout)")
        XCTAssertTrue(stdout.contains("child=/plugins/gmcc"),
                      "values reached the shell but not child processes: \(stdout)")
    }

    func testShimResolvesGmccRootAtCallTime() {
        XCTAssertTrue(GmccEnvironment.shimScript
            .contains(#"exec "${GMCC_ROOT:-$HOME/gmcc}/bin/gmcc_hook" "$@""#))
        XCTAssertTrue(GmccEnvironment.shimScript.hasPrefix("#!/bin/sh"))
    }

    func testCheckFlagsCkfsRootMismatch() {
        // check() reads the claim from the process env; the db side comes in
        // via the response. Point the response somewhere the env can't be.
        let response = PathsGetResponse(
            gmccRoot: Paths.root.path, dbPath: "", socketPath: "", backupsRoot: "",
            ckfsRoot: "/definitely/not/the/env/value",
            kbiteRoot: "", kbiteOpenRoot: "", kbiteDigestedRoot: "")
        // Only meaningful when the env carries GMCC_CKFS_ROOT at all; the
        // finding is required whenever it does.
        if let claimed = ProcessInfo.processInfo.environment["GMCC_CKFS_ROOT"],
           !claimed.isEmpty {
            let findings = GmccEnvironment.check(response)
            XCTAssertTrue(findings.contains { $0.code == "ckfs_root_mismatch" })
        }
        // Agreement produces no ckfs finding.
        let agreeing = PathsGetResponse(
            gmccRoot: Paths.root.path, dbPath: "", socketPath: "", backupsRoot: "",
            ckfsRoot: GmccEnvironment.fallbackCkfsRoot.path,
            kbiteRoot: "", kbiteOpenRoot: "", kbiteDigestedRoot: "")
        XCTAssertFalse(GmccEnvironment.check(agreeing).contains { $0.code == "ckfs_root_mismatch" })
    }
}
