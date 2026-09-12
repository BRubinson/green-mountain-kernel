import XCTest

// @testable, not a plain import: the hook logic's types are INTERNAL to the kit
// on purpose — HookRunner is their only production caller — and the tests reach
// them here rather than the surface being widened to suit them.
@testable import GMCCDaemonKit

/// The hook family's parsing half, under test because the failure this work
/// answers was a hook that died on its first line for weeks with nobody
/// looking. Every decision `gm hook` makes before it opens a socket is
/// reachable from here: the payload decode, the agent discriminator, the
/// sandbox marker, the Bash write allowlist and the git kind classifier.
///
/// THE FIXTURES ARE THE PROBE PAYLOADS recorded in prompt 9's own detail,
/// which is why they carry field sets rather than a tidy minimum: the primary
/// shape carries `effort` and no agent identity, and the four spawn shapes
/// report four different things in `agent_type`. Elided values in the
/// transcript (`"transcript_path":"..."`) are filled in with concrete paths;
/// every field NAME and every probed agent_id / agent_type is verbatim.
final class HookPayloadTests: XCTestCase {

    private var fixtureRoot: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        fixtureRoot = fm.temporaryDirectory
            .appendingPathComponent("hook-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: fixtureRoot)
    }

    // MARK: - Fixtures

    /// The PRIMARY's PostToolUse shape: session_id, transcript_path, cwd,
    /// prompt_id, permission_mode, effort, hook_event_name, tool_name,
    /// tool_input, tool_response, tool_use_id, duration_ms — and NO agent_id.
    private func primaryEdit(cwd: String, filePath: String) -> Data {
        Data("""
        {"session_id":"75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
         "transcript_path":"/Users/probe/.claude/projects/-repo/75730a4f.jsonl",
         "cwd":"\(cwd)",
         "prompt_id":"0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04",
         "permission_mode":"acceptEdits",
         "effort":"medium",
         "hook_event_name":"PostToolUse",
         "tool_name":"Edit",
         "tool_input":{"file_path":"\(filePath)","old_string":"a","new_string":"b"},
         "tool_response":{"filePath":"\(filePath)","structuredPatch":[
            {"oldStart":12,"oldLines":3,"newStart":12,"newLines":4,
             "lines":["-a","+b","+c"," d"]},
            {"oldStart":40,"oldLines":2,"newStart":41,"newLines":0,
             "lines":["-gone","-also gone"]}]},
         "tool_use_id":"toolu_01PrimaryEdit",
         "duration_ms":412}
        """.utf8)
    }

    /// The SUBAGENT shape: everything the primary carries PLUS agent_id and
    /// agent_type, and no `effort`. `shape` supplies the probed pair.
    private func agentEdit(
        cwd: String, filePath: String, agentId: String, agentType: String
    ) -> Data {
        Data("""
        {"session_id":"75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
         "transcript_path":"/Users/probe/.claude/projects/-repo/75730a4f.jsonl",
         "cwd":"\(cwd)",
         "prompt_id":"0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04",
         "permission_mode":"default",
         "hook_event_name":"PostToolUse",
         "agent_id":"\(agentId)",
         "agent_type":"\(agentType)",
         "tool_name":"Write",
         "tool_input":{"file_path":"\(filePath)","content":"x"},
         "tool_response":{"type":"create","filePath":"\(filePath)","structuredPatch":[]},
         "tool_use_id":"toolu_01AgentWrite",
         "duration_ms":88}
        """.utf8)
    }

    private func bashCall(cwd: String, command: String) -> Data {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("""
        {"session_id":"75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
         "transcript_path":"/Users/probe/.claude/projects/-repo/75730a4f.jsonl",
         "cwd":"\(cwd)",
         "prompt_id":"0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04",
         "permission_mode":"acceptEdits",
         "hook_event_name":"PostToolUse",
         "tool_name":"Bash",
         "tool_input":{"command":"\(escaped)","description":"probe"},
         "tool_response":{"stdout":"","stderr":"","interrupted":false,"isImage":false},
         "tool_use_id":"toolu_01BashCall",
         "duration_ms":133}
        """.utf8)
    }

    // MARK: - The payload

    func testPrimaryPayloadDecodesEveryCapturedColumnAndNoAgentIdentity() throws {
        let payload = try XCTUnwrap(HookPayload.decode(
            primaryEdit(cwd: "/repo", filePath: "/repo/Sources/File.swift")))

        XCTAssertEqual(payload.sessionId, "75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f")
        XCTAssertEqual(payload.hookEventName, "PostToolUse")
        XCTAssertEqual(payload.cwd, "/repo")
        XCTAssertEqual(
            payload.transcriptPath, "/Users/probe/.claude/projects/-repo/75730a4f.jsonl")
        XCTAssertEqual(payload.permissionMode, "acceptEdits")
        XCTAssertEqual(payload.toolName, "Edit")
        XCTAssertEqual(payload.toolUseId, "toolu_01PrimaryEdit")
        XCTAssertEqual(payload.durationMs, 412)
        XCTAssertEqual(payload.filePath, "/repo/Sources/File.swift")

        // THE DISCRIMINATOR. Absence is the whole test: the primary carries no
        // agent identity, so a primary write has nothing to attribute to an
        // agent and nothing to point a registration FK at.
        XCTAssertNil(payload.agentId)
        XCTAssertNil(payload.agentType)
    }

    /// THE TRAP. The payload field is spelled `prompt_id` and it is Claude
    /// Code's TURN id. It lands on `claudeTurnId` and there is no member on
    /// this type that would let it be mistaken for a gmcc prompt uuid.
    func testPromptIdLandsOnTheTurnIdAndNeverLooksLikeAPromptUuid() throws {
        let payload = try XCTUnwrap(HookPayload.decode(
            primaryEdit(cwd: "/repo", filePath: "/repo/a.swift")))
        XCTAssertEqual(payload.claudeTurnId, "0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04")
    }

    func testStructuredPatchExpandsToNewSideRanges() throws {
        let payload = try XCTUnwrap(HookPayload.decode(
            primaryEdit(cwd: "/repo", filePath: "/repo/a.swift")))
        let ranges = StructuredPatchExpander.expand(payload.structuredPatch)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].lineStart, 12)
        XCTAssertEqual(ranges[0].lineEnd, 15)
        XCTAssertEqual(ranges[0].changedContent, "-a\n+b\n+c\n d")
        // A hunk that deletes everything it touches reports newLines 0; the
        // range collapses onto the line the deletion landed on rather than
        // being zero-height and unreadable.
        XCTAssertEqual(ranges[1].lineStart, 41)
        XCTAssertEqual(ranges[1].lineEnd, 41)
    }

    /// The four spawn shapes probed live. agent_type reports something
    /// different in each, which is exactly why it is stored as a LABEL and
    /// the role comes from the spawner instead.
    func testEverySpawnShapeDecodesItsProbedIdentity() throws {
        let shapes: [(agentId: String, agentType: String)] = [
            // plain subagent — the subagent_type
            ("a9056593c66326b3a", "gmcc:doper"),
            // workflow agent, bare — a generic literal identifying nothing
            ("a349d9808be1c1472", "workflow-subagent"),
            // workflow agent with agentType set — the real type
            ("a532597540f783369", "gmcc:code-explorer"),
            // named teammate — the NAME, not the type. Its actual
            // subagent_type was gmcc:code-explorer and the payload says
            // "conservative"; teammates are in-process NAMED subagents, not
            // separate sessions, and they DO carry an agent_id.
            ("aconservative-d32a81b4b9dfa222", "conservative"),
        ]
        for shape in shapes {
            let payload = try XCTUnwrap(HookPayload.decode(agentEdit(
                cwd: "/repo", filePath: "/repo/a.swift",
                agentId: shape.agentId, agentType: shape.agentType)))
            XCTAssertEqual(payload.agentId, shape.agentId)
            XCTAssertEqual(payload.agentType, shape.agentType)
            // Opaque: `a<hex>` and `a<name>-<hex>` both arrive intact, and
            // nothing in this path splits either one apart.
            XCTAssertEqual(payload.sessionId, "75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
                           "every spawn shape shares the primary's session_id")
        }
    }

    /// The two SubagentStart payloads from the probe, verbatim in shape: this
    /// is the event that makes registration universal, and it carries the
    /// agent_id, the conversation and the turn before the agent can write.
    func testSubagentStartProbePayloadsDecode() throws {
        let first = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
         "transcript_path":"/Users/probe/.claude/projects/-repo/75730a4f.jsonl",
         "cwd":"/repo",
         "prompt_id":"0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04",
         "agent_id":"aa8aba4e7f40075e5",
         "agent_type":"general-purpose",
         "hook_event_name":"SubagentStart"}
        """.utf8)))
        XCTAssertEqual(first.agentId, "aa8aba4e7f40075e5")
        XCTAssertEqual(first.agentType, "general-purpose")
        XCTAssertEqual(first.hookEventName, "SubagentStart")
        XCTAssertEqual(first.claudeTurnId, "0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04")
        // No tool fired, so there is nothing to record — only an identity.
        XCTAssertNil(first.toolName)
        XCTAssertNil(first.filePath)

        let second = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"75730a4f-1d0a-4f2b-9c3e-8a6b5d4c3e2f",
         "transcript_path":"/Users/probe/.claude/projects/-repo/75730a4f.jsonl",
         "cwd":"/repo",
         "prompt_id":"0b8aef6b-9c1d-4e2a-8b7f-3d5c6a1e9f04",
         "agent_id":"a59cac90a3dff1164",
         "agent_type":"gmcc:doper",
         "hook_event_name":"SubagentStart"}
        """.utf8)))
        XCTAssertEqual(second.agentId, "a59cac90a3dff1164")
        XCTAssertEqual(second.agentType, "gmcc:doper")
    }

    /// tool_response's shape varies per tool and some tools return a bare
    /// string. A strict decode would throw on the sibling and lose a change
    /// that was perfectly recordable from tool_input.
    func testAToolResponseThatIsNotAnObjectStillDecodes() throws {
        let payload = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"s","cwd":"/repo","tool_name":"Edit","tool_use_id":"t",
         "tool_input":{"file_path":"/repo/a.swift"},
         "tool_response":"ok"}
        """.utf8)))
        XCTAssertEqual(payload.filePath, "/repo/a.swift")
        XCTAssertEqual(payload.structuredPatch, [])
    }

    func testUnparseableStdinIsNothingAtAll() {
        XCTAssertNil(HookPayload.decode(Data()))
        XCTAssertNil(HookPayload.decode(Data("not json".utf8)))
        XCTAssertNil(HookPayload.decode(Data("[1,2,3]".utf8)))
    }

    /// An empty string is an ABSENCE. A shim that re-serialises a payload can
    /// turn an omitted agent_id into "", and an empty agent_id read as present
    /// would hand the primary's write a registration it must not have.
    func testEmptyStringsDecodeAsAbsent() throws {
        let payload = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"s","cwd":"/repo","agent_id":"","agent_type":"",
         "tool_name":"Edit","tool_input":{"file_path":"/repo/a.swift"}}
        """.utf8)))
        XCTAssertNil(payload.agentId)
        XCTAssertNil(payload.agentType)
    }

    // MARK: - The sandbox marker

    /// WITHOUT THIS A SANDBOX SESSION'S HOOKS WRITE THE PROD DB. The marker is
    /// parsed as data, never sourced, and the walk climbs from the payload's
    /// cwd so a tool call in a subdirectory still finds the snapshot root.
    func testSandboxMarkerIsFoundByClimbingFromThePayloadCwd() throws {
        let repo = fixtureRoot.appendingPathComponent("snapshot", isDirectory: true)
        let deep = repo.appendingPathComponent("Sources/Deep", isDirectory: true)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try """
        # Written by gm sandbox refresh — sourced by gmcc_session_startup.sh so any
        # Claude session inside this snapshot auto-sandboxes.
        export GMCC_ROOT="/tmp/sandbox/runtime"
        export GMCC_CKFS_ROOT="/tmp/sandbox/ckfs"
        """.write(
            to: repo.appendingPathComponent(".gmcc_sandbox"),
            atomically: true, encoding: .utf8)

        let roots = try XCTUnwrap(SandboxMarker.find(startingAt: deep.path))
        XCTAssertEqual(roots.gmccRoot, "/tmp/sandbox/runtime")
        XCTAssertEqual(roots.ckfsRoot, "/tmp/sandbox/ckfs")
    }

    func testNoMarkerMeansNoRetarget() throws {
        let plain = fixtureRoot.appendingPathComponent("plain", isDirectory: true)
        try fm.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertNil(SandboxMarker.find(startingAt: plain.path))
    }

    // MARK: - The Bash write allowlist: what it RECORDS

    private func extracted(_ command: String, cwd: String = "/repo") -> [String] {
        BashWritePaths.extract(command: command, cwd: cwd).map { target in
            "\(target.intent == .delete ? "delete" : "write") \(target.path)"
        }
    }

    func testRedirectionsRecordTheirTarget() {
        XCTAssertEqual(extracted("echo hi > out.txt"), ["write /repo/out.txt"])
        XCTAssertEqual(extracted("echo hi >> log.txt"), ["write /repo/log.txt"])
        XCTAssertEqual(extracted("swift build > /repo/build.log"), ["write /repo/build.log"])
        // A leading fd belongs to the operator. Left in the word list it would
        // look like a path named `2`.
        XCTAssertEqual(extracted("swift build 2> err.txt"), ["write /repo/err.txt"])
        // `&` splits, so `2>&1` leaves the operator with no operand at all.
        XCTAssertEqual(extracted("swift build > log.txt 2>&1"), ["write /repo/log.txt"])
    }

    func testTeeRecordsEveryFileItWrites() {
        XCTAssertEqual(extracted("cat a | tee -a notes.txt"), ["write /repo/notes.txt"])
        XCTAssertEqual(
            extracted("echo x | tee one.txt two.txt"),
            ["write /repo/one.txt", "write /repo/two.txt"])
    }

    func testInPlaceSedAndPerlRecordTheirFilesInEverySpelling() {
        // The macOS idiom: -i takes an empty suffix as its own word, which is
        // consumed as the suffix rather than mistaken for the script.
        XCTAssertEqual(
            extracted("sed -i '' 's/a/b/' Sources/A.swift Sources/B.swift"),
            ["write /repo/Sources/A.swift", "write /repo/Sources/B.swift"])
        // GNU: no suffix word, the script is the first positional.
        XCTAssertEqual(extracted("sed -i 's/a/b/' A.swift"), ["write /repo/A.swift"])
        // An attached suffix, and a script supplied by -e so no positional
        // script is consumed.
        XCTAssertEqual(extracted("sed -i.bak -e 's/a/b/' A.swift"), ["write /repo/A.swift"])
        XCTAssertEqual(extracted("perl -pi -e 's/a/b/' A.swift"), ["write /repo/A.swift"])
        XCTAssertEqual(extracted("perl -i.bak -pe 's/a/b/' A.swift"), ["write /repo/A.swift"])
    }

    func testSedWithoutInPlaceWritesNothing() {
        // It prints to stdout; the file is untouched.
        XCTAssertEqual(extracted("sed 's/a/b/' A.swift"), [])
    }

    func testCopyMoveRemoveAndTouch() {
        XCTAssertEqual(extracted("cp a.txt b.txt"), ["write /repo/b.txt"])
        XCTAssertEqual(extracted("install -m 755 bin/x /repo/out/x"), ["write /repo/out/x"])
        // A move is TWO facts: the destination appears and the source leaves.
        XCTAssertEqual(
            extracted("mv old.txt new.txt"),
            ["write /repo/new.txt", "delete /repo/old.txt"])
        XCTAssertEqual(
            extracted("rm -rf build/a.o build/b.o"),
            ["delete /repo/build/a.o", "delete /repo/build/b.o"])
        XCTAssertEqual(extracted("touch marker"), ["write /repo/marker"])
    }

    func testAssignmentsAndWrappersArePeeledBeforeDispatch() {
        XCTAssertEqual(
            extracted("LC_ALL=C env sed -i '' 's/a/b/' A.swift"),
            ["write /repo/A.swift"])
        // The peel looks at the FIRST WORD only: an `=` inside an argument
        // must not eat the command word.
        XCTAssertEqual(
            extracted(#"sed -i '' "s/rating=0/rating=1/" A.swift"#),
            ["write /repo/A.swift"])
    }

    func testSeparatorsMakeEachCommandItsOwnPosition() {
        XCTAssertEqual(
            extracted("rm old.txt && touch new.txt"),
            ["delete /repo/old.txt", "write /repo/new.txt"])
        XCTAssertEqual(extracted("x=$(rm gone.txt)"), ["delete /repo/gone.txt"])
        // Later mentions win: the path ends the command line written.
        XCTAssertEqual(extracted("rm a.txt; touch a.txt"), ["write /repo/a.txt"])
    }

    // MARK: - The Bash write allowlist: the DOCUMENTED GAPS

    /// These record NOTHING, silently, and that is the accepted cost of a
    /// mechanism that cannot misattribute. Each of these is a real write that
    /// produces zero rows.
    func testTheDocumentedGapsRecordNothing() {
        // Every interpreter heredoc: the body is data whose lines are
        // indistinguishable from commands without parsing the shell.
        XCTAssertEqual(extracted("python - <<EOF\nopen('x.txt','w').write('y')\nEOF"), [])
        XCTAssertEqual(extracted("cat <<'EOF' > out.txt\nbody\nEOF"), [])
        // A build system, a script and a patch tool all write files this
        // parser never sees named.
        XCTAssertEqual(extracted("make install"), [])
        XCTAssertEqual(extracted("./scripts/build_daemon.sh"), [])
        XCTAssertEqual(extracted("git apply fix.patch"), [])
        XCTAssertEqual(extracted("swift build"), [])
        // Unbalanced quotes: the scanner cannot know where the word
        // boundaries were, so the whole command records nothing.
        XCTAssertEqual(extracted("echo 'unterminated > out.txt"), [])
        XCTAssertEqual(extracted(#"echo "unterminated > out.txt"#), [])
        // Nothing here expands a variable or a glob, so neither can be a path.
        XCTAssertEqual(extracted("rm $TARGET"), [])
        XCTAssertEqual(extracted("rm build/*.o"), [])
        XCTAssertEqual(extracted("echo x > $LOG"), [])
        // Not a file anyone wants a history row for.
        XCTAssertEqual(extracted("swift build > /dev/null"), [])
    }

    /// A path named inside a quoted string is TEXT, not a command position.
    /// Splitting on the separator inside it would manufacture a deletion out
    /// of a commit message — the mistake the write guard's scanner was
    /// written to avoid, and the reason its rules are ported rather than
    /// reinvented.
    func testQuotedTextIsNeverACommandPosition() {
        XCTAssertEqual(extracted(#"git commit -m "cleanup; rm -rf build""#), [])
        XCTAssertEqual(extracted("echo 'rm important.txt'"), [])
        XCTAssertEqual(extracted(#"rg "sed -i" scripts/"#), [])
        XCTAssertEqual(extracted(#"echo "a > b""#), [])
        XCTAssertEqual(extracted("echo x \\> notafile"), [])
    }

    /// The scan stops at the heredoc, and everything BEFORE it still counts —
    /// the stop is a bound on what can be read, not an abandonment of what
    /// already was.
    func testWorkBeforeAHeredocIsStillRecorded() {
        XCTAssertEqual(
            extracted("touch first.txt && python - <<EOF\nopen('x','w')\nEOF"),
            ["write /repo/first.txt"])
    }

    func testARunawayCommandCannotWriteUnboundedHistory() {
        let command = (1...(BashWritePaths.maxTargets + 50))
            .map { "rm f\($0).o" }
            .joined(separator: "; ")
        XCTAssertEqual(extracted(command).count, BashWritePaths.maxTargets)
    }

    // MARK: - Kind, confirmed by git

    /// A real repo: `git status --porcelain -- <path>` is the classifier, and
    /// a fake .git directory cannot answer it.
    private func makeRepo() throws -> String {
        let repo = fixtureRoot.appendingPathComponent("repo", isDirectory: true)
        try fm.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "-q"], in: repo)
        try "one\n".write(
            to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["-c", "user.email=t@example.com", "-c", "user.name=t",
                 "commit", "-q", "-m", "seed"], in: repo)
        return repo.standardizedFileURL.path
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }

    func testGitClassifiesThePathTheCommandNamed() throws {
        let repo = try makeRepo()
        func classify(_ path: String, _ declared: BashWritePaths.Intent) -> ChangeKind? {
            GitPathClassifier.classify(relativePath: path, repoRoot: repo, declared: declared)
        }

        // Untracked → a create.
        try "new\n".write(
            to: URL(fileURLWithPath: repo).appendingPathComponent("fresh.txt"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(classify("fresh.txt", .write), .create)

        // Tracked and modified → an edit.
        try "two\n".write(
            to: URL(fileURLWithPath: repo).appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(classify("tracked.txt", .write), .edit)

        // Tracked and removed → a delete, whatever the command claimed.
        try fm.removeItem(atPath: repo + "/tracked.txt")
        XCTAssertEqual(classify("tracked.txt", .write), .delete)

        // Untracked and gone: git has nothing to say and neither does the
        // filesystem, so the COMMAND's intent is the answer.
        XCTAssertEqual(classify("never-existed.txt", .delete), .delete)
    }

    /// THE SAFETY NET under the whole allowlist. A `sed` script or a stray
    /// argument misread as a filename resolves to a path git does not know
    /// and that does not exist — and that combination records nothing rather
    /// than filing a change against a file that was never a file.
    func testAnArgumentThatIsNotAPathRecordsNothing() throws {
        let repo = try makeRepo()
        XCTAssertNil(GitPathClassifier.classify(
            relativePath: "s/a/b/", repoRoot: repo, declared: .write))
    }

    func testAPathOutsideTheBootedRepoIsNotRepoRelative() {
        XCTAssertEqual(
            GitPathClassifier.repoRelative("/repo/Sources/A.swift", repoRoot: "/repo"),
            "Sources/A.swift")
        // $HOME is itself a git toplevel on plenty of machines, and the ckfs
        // and kbite trees are repos too. Foreign paths would land as junk
        // rows in an append-only db.
        XCTAssertNil(GitPathClassifier.repoRelative("/elsewhere/A.swift", repoRoot: "/repo"))
        XCTAssertNil(GitPathClassifier.repoRelative("/repo", repoRoot: "/repo"))
    }

    // MARK: - Payload → targets

    func testAWriteOfANewFileIsACreateCarryingItsExactRanges() throws {
        let repo = try makeRepo()
        let payload = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"s","cwd":"\(repo)","tool_name":"Write","tool_use_id":"t",
         "tool_input":{"file_path":"\(repo)/fresh.txt","content":"x"},
         "tool_response":{"structuredPatch":[
            {"oldStart":1,"oldLines":0,"newStart":1,"newLines":2,"lines":["+a","+b"]}]}}
        """.utf8)))
        try "x\n".write(
            to: URL(fileURLWithPath: repo).appendingPathComponent("fresh.txt"),
            atomically: true, encoding: .utf8)

        let targets = HookWriteTargets.resolve(payload: payload, repoRoot: repo)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].relativePath, "fresh.txt")
        XCTAssertEqual(targets[0].changeKind, .create)
        XCTAssertEqual(targets[0].origin, FileChangeOrigin.hook)
        XCTAssertEqual(targets[0].ranges.count, 1)
        XCTAssertEqual(targets[0].ranges[0].lineStart, 1)
        XCTAssertEqual(targets[0].ranges[0].lineEnd, 2)
    }

    /// An inferred row is never indistinguishable from an exact one: the
    /// allowlist's rows carry their own origin, and they carry no ranges
    /// because a command line says nothing about line numbers.
    func testACommandDerivedRowSaysSoInItsOrigin() throws {
        let repo = try makeRepo()
        let payload = try XCTUnwrap(HookPayload.decode(
            bashCall(cwd: repo, command: "rm tracked.txt")))
        try fm.removeItem(atPath: repo + "/tracked.txt")

        let targets = HookWriteTargets.resolve(payload: payload, repoRoot: repo)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].relativePath, "tracked.txt")
        XCTAssertEqual(targets[0].changeKind, .delete)
        XCTAssertEqual(targets[0].origin, FileChangeOrigin.command)
        XCTAssertEqual(targets[0].ranges, [])
    }

    /// THE TOOL ALLOWLIST. A tool that merely READ a file carries a
    /// `file_path` too, and a permissive rule would record a change that
    /// never happened — a wrong row, which is worse than a missing one.
    func testOnlyTheAllowlistedToolsProduceTargets() throws {
        let repo = try makeRepo()
        let payload = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"s","cwd":"\(repo)","tool_name":"Read","tool_use_id":"t",
         "tool_input":{"file_path":"\(repo)/tracked.txt"}}
        """.utf8)))
        XCTAssertEqual(HookWriteTargets.resolve(payload: payload, repoRoot: repo), [])
    }

    func testAToolCallThatNamedNoPathProducesNothing() throws {
        let repo = try makeRepo()
        let payload = try XCTUnwrap(HookPayload.decode(
            bashCall(cwd: repo, command: "swift test")))
        XCTAssertEqual(HookWriteTargets.resolve(payload: payload, repoRoot: repo), [])
    }

    func testAnEditOutsideTheBootedRepoProducesNothing() throws {
        let repo = try makeRepo()
        let payload = try XCTUnwrap(HookPayload.decode(Data("""
        {"session_id":"s","cwd":"\(repo)","tool_name":"Edit","tool_use_id":"t",
         "tool_input":{"file_path":"/somewhere/else/A.swift"}}
        """.utf8)))
        XCTAssertEqual(HookWriteTargets.resolve(payload: payload, repoRoot: repo), [])
    }
}
