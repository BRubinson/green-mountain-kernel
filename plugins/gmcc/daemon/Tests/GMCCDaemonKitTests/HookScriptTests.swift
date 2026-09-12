import XCTest

/// The shell hooks, EXECUTED — under an environment that has been emptied.
///
/// Every test here runs the equivalent of
///
///     env -i HOME=$tmp PATH=/usr/bin:/bin bash <hook> <args>
///
/// and the scrub is the entire point. The bug this family of scripts was
/// rewritten to answer was a hook that resolved `gm` through PATH and gated on
/// `GMCC_BOOTED` — both inherited from a session provisioning that a hook
/// process never sees. In the developer's own shell those scripts pass every
/// test that can be written for them, because the developer's shell has
/// `~/gmcc/bin` on PATH and GMCC_BOOTED set. A test that inherits the
/// environment does not test this bug; it reproduces the conditions that hid
/// it for weeks.
///
/// So the environment carries exactly two names, neither of them GMCC's, and
/// `$HOME` points at a temp tree holding a fake `gm` that records the argv and
/// the stdin it was handed. The script under test is COPIED into that tree:
/// resolution climbs from the script's own directory looking for a sandbox
/// marker, so running the checkout's copy would resolve differently depending
/// on whether the checkout is itself a snapshot.
///
/// `DocsContractTests.testNonBootHookScriptsResolveGmWithoutInheritedEnv` is
/// the static half of the same contract — it bans the spellings, this runs the
/// result.
final class HookScriptTests: XCTestCase {

    // MARK: - The scrubbed harness

    /// plugins/gmcc/scripts, located from this file.
    private var scriptsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GMCCDaemonKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // daemon
            .deletingLastPathComponent()   // plugins/gmcc
            .appendingPathComponent("scripts", isDirectory: true)
    }

    /// One run's temp world, torn down with the test.
    private final class Sandbox {
        let root: URL
        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("gmcc-hook-tests-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        func dir(_ relative: String) throws -> URL {
            let url = root.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func write(_ contents: String, to relative: String, executable: Bool = false) throws -> URL {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            if executable {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            return url
        }

        func read(_ relative: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }

        func exists(_ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
        }
    }

    /// Copy a shipped hook script into the temp tree at `<relativeDir>/<name>`.
    /// Nothing above a temp directory carries a `.gmcc_sandbox` marker, so a
    /// copy placed here resolves to `$HOME/gmcc/bin/gmcc_hook` unless the test puts a
    /// marker there on purpose.
    private func install(
        _ name: String, into sandbox: Sandbox, at relativeDir: String = "plugin/scripts"
    ) throws -> URL {
        let source = scriptsDir.appendingPathComponent(name)
        let destination = try sandbox.dir(relativeDir).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    /// A stand-in `gm` that records what it was called with and prints
    /// `stdout`. `recordDir` is baked in literally because the environment the
    /// script runs under carries nothing this could be passed through.
    private func installFakeGm(
        in sandbox: Sandbox, at relativePath: String, recordDir: String, stdout: String = ""
    ) throws {
        let records = try sandbox.dir(recordDir)
        let body = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(records.path)/argv'
        cat > '\(records.path)/stdin'
        cat <<'GM_STDOUT_EOF'
        \(stdout)
        GM_STDOUT_EOF
        """
        _ = try sandbox.write(body, to: relativePath, executable: true)
    }

    private struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// `env -i HOME=<sandbox> PATH=/usr/bin:/bin bash <script> <arguments>`.
    /// The environment dictionary IS the scrub — it replaces the parent's
    /// rather than adding to it, so no GMCC_* and no `~/gmcc/bin` reaches the
    /// child by any route.
    private func run(
        _ script: URL, _ arguments: [String] = [], stdin: String = "", home: URL
    ) throws -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try? inPipe.fileHandleForWriting.close()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            status: process.terminationStatus,
            stdout: String(data: out, encoding: .utf8) ?? "",
            stderr: String(data: err, encoding: .utf8) ?? "")
    }

    /// A PostToolUse payload with the fields the capture path reads.
    private let postToolUsePayload = """
    {"session_id":"6d3f1a90-hook-test","hook_event_name":"PostToolUse",\
    "cwd":"/Users/nobody/repo","tool_name":"Edit","tool_use_id":"toolu_01HOOK",\
    "tool_input":{"file_path":"/Users/nobody/repo/a.swift"},"duration_ms":12}
    """

    // MARK: - gmcc_hook.sh

    /// The payload reaches `gm hook post-tool-use` BYTE FOR BYTE. The shim
    /// parses nothing: if it ever starts to, the capture surface's fixtures
    /// stop describing what the daemon actually receives.
    func testPostToolUsePayloadReachesGmWithNoInheritedEnvironment() throws {
        let sandbox = try Sandbox()
        let script = try install("gmcc_hook.sh", into: sandbox)
        try installFakeGm(in: sandbox, at: "gmcc/bin/gmcc_hook", recordDir: "rec")

        let result = try run(
            script, ["post-tool-use"], stdin: postToolUsePayload, home: sandbox.root)

        XCTAssertEqual(result.status, 0, "hook exited non-zero: \(result.stderr)")
        XCTAssertEqual(sandbox.read("rec/argv"), "hook\npost-tool-use\n")
        XCTAssertEqual(sandbox.read("rec/stdin"), postToolUsePayload)
    }

    /// The same shim, the other event — one script, the event as argv, which
    /// is the whole reason there is no second prelude to drift from this one.
    func testSubagentStartPayloadReachesGmWithNoInheritedEnvironment() throws {
        let sandbox = try Sandbox()
        let script = try install("gmcc_hook.sh", into: sandbox)
        try installFakeGm(in: sandbox, at: "gmcc/bin/gmcc_hook", recordDir: "rec")
        let payload = """
        {"session_id":"6d3f1a90-hook-test","hook_event_name":"SubagentStart",\
        "cwd":"/Users/nobody/repo","agent_id":"agent-1","agent_type":"gmcc:code-explorer"}
        """

        let result = try run(script, ["subagent-start"], stdin: payload, home: sandbox.root)

        XCTAssertEqual(result.status, 0, "hook exited non-zero: \(result.stderr)")
        XCTAssertEqual(sandbox.read("rec/argv"), "hook\nsubagent-start\n")
        XCTAssertEqual(sandbox.read("rec/stdin"), payload)
    }

    /// No binary on disk: exit 0, nothing on stdout, NOTHING ON STDERR. A hook
    /// that complains is a hook that decorates every turn of an install that
    /// has not built the daemon yet, and on PreToolUse a non-zero exit is read
    /// as a decision.
    func testMissingGmBinaryIsASilentExitZero() throws {
        let sandbox = try Sandbox()
        let script = try install("gmcc_hook.sh", into: sandbox)

        let result = try run(
            script, ["post-tool-use"], stdin: postToolUsePayload, home: sandbox.root)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
    }

    /// No event name: exit 0 without running anything. `gm hook` with no
    /// subcommand prints usage, and usage on a PostToolUse hook's stdout is
    /// injected into the transcript.
    func testMissingEventArgumentRunsNothing() throws {
        let sandbox = try Sandbox()
        let script = try install("gmcc_hook.sh", into: sandbox)
        try installFakeGm(in: sandbox, at: "gmcc/bin/gmcc_hook", recordDir: "rec")

        let result = try run(script, [], stdin: postToolUsePayload, home: sandbox.root)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertFalse(sandbox.exists("rec/argv"), "gm ran with no event to hand it")
    }

    /// A SANDBOX SNAPSHOT'S HOOK MUST DRIVE THE SNAPSHOT'S RUNTIME. The script
    /// ships inside the snapshot's repo clone, so climbing from its own
    /// location finds the clone's `.gmcc_sandbox` and the binary named there.
    /// Without this a snapshot session's every edit lands in the PROD db —
    /// the hazard that removing the inherited env creates, since a sandbox
    /// launcher's `GMCC_ROOT` is exactly the kind of variable a hook does not
    /// inherit.
    func testSandboxMarkerRetargetsTheBinary() throws {
        let sandbox = try Sandbox()
        let snapshotRoot = try sandbox.dir("snapshot/runtime")
        _ = try sandbox.write(
            """
            export GMCC_ROOT="\(snapshotRoot.path)"
            export GMCC_CKFS_ROOT="\(sandbox.root.path)/snapshot/ckfs"
            """,
            to: "snapshot/repo/.gmcc_sandbox")
        let script = try install(
            "gmcc_hook.sh", into: sandbox, at: "snapshot/repo/plugins/gmcc/scripts")
        // The prod-shaped binary is present too: this test fails if the walk
        // is skipped, not merely if it finds nothing.
        try installFakeGm(in: sandbox, at: "gmcc/bin/gmcc_hook", recordDir: "rec-prod")
        try installFakeGm(in: sandbox, at: "snapshot/runtime/bin/gmcc_hook", recordDir: "rec-snapshot")

        let result = try run(
            script, ["post-tool-use"], stdin: postToolUsePayload, home: sandbox.root)

        XCTAssertEqual(result.status, 0, "hook exited non-zero: \(result.stderr)")
        XCTAssertEqual(sandbox.read("rec-snapshot/argv"), "hook\npost-tool-use\n")
        XCTAssertFalse(
            sandbox.exists("rec-prod/argv"),
            "the snapshot's hook drove the PROD binary — its writes would land in the prod db")
    }
}
