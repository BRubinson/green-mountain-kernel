import XCTest
@testable import GMCCDaemonKit

/// Doc drift as a build failure (the CheatsheetTests precedent, extended).
/// Walks the plugin's doc tree (commands/, skills/, prompts/, output-styles/)
/// and refuses the classes of rot this cleanup retired: hardcoded gm binary
/// paths, the retired session env family, the retired DOPE expansion, the
/// retired ~/.zshrc block, and `--adopt` leaking into bot workflows.
///
/// Three of these also walk `daemon/Sources`. That widening is the point: the
/// worst offenders of the SESSION_BASE / `.gmcc/dope` rot were the COMPILED
/// cheatsheet and the CLI `--help` abstracts, which a docs-only walk cannot
/// see even though they reach every session.
///
/// The last section is not about prose at all: it is the HOOK/LAUNCHER
/// CONTRACT. `hooks.json`, `settings.json` and `.mcp.json` are the only files
/// in this plugin whose blast radius is every turn of every session in every
/// booted repo — a malformed entry there wedges turns that have nothing to do
/// with GMCC — and until these tests existed the entire mitigation was a human
/// remembering to validate the JSON before committing. Nothing here needs a
/// daemon, a db or a network: it parses three files, stats the paths they
/// name, and runs `bash -n`.
///
/// Allowlists are deliberate and commented — keep them SHORT; every entry
/// names why it is exempt.
final class DocsContractTests: XCTestCase {

    /// plugins/gmcc/, located from this file: Tests/GMCCDaemonKitTests/X.swift
    /// → daemon/ → plugins/gmcc/.
    private var pluginRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // drop DocsContractTests.swift
            .deletingLastPathComponent()   // drop GMCCDaemonKitTests
            .deletingLastPathComponent()   // drop Tests
            .deletingLastPathComponent()   // drop daemon → plugins/gmcc
    }

    private func docFiles() throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in ["commands", "skills", "prompts", "output-styles"] {
            let root = pluginRoot.appendingPathComponent(dir, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "md" { out.append(url) }
            }
        }
        XCTAssertGreaterThan(out.count, 20, "doc tree walk looks broken: \(pluginRoot.path)")
        return out
    }

    private func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: pluginRoot.path + "/", with: "")
    }

    /// plugins/gmcc/daemon/Sources — the CLI help text, cheatsheet body and
    /// doc comments that a `.md`-only walk misses.
    private func swiftFiles() throws -> [URL] {
        let fm = FileManager.default
        let root = pluginRoot.appendingPathComponent("daemon/Sources", isDirectory: true)
        var out: [URL] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { out.append(url) }
        }
        XCTAssertGreaterThan(out.count, 20, "source tree walk looks broken: \(root.path)")
        return out
    }

    /// plugins/gmcc/agents — the agent definitions. `docFiles()` deliberately
    /// does not walk them (they are frontmatter + identity, not reference
    /// prose), but a retired agent NAME lives here first and reaches every
    /// spawn, so the retired-agent sweep below reads them too.
    private func agentFiles() throws -> [URL] {
        let fm = FileManager.default
        let root = pluginRoot.appendingPathComponent("agents", isDirectory: true)
        var out: [URL] = []
        let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "md" { out.append(url) }
        }
        XCTAssertGreaterThan(out.count, 3, "agent tree walk looks broken: \(root.path)")
        return out
    }

    private func violations(
        pattern: String, allowFiles: Set<String>, allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        try violations(in: try docFiles(), pattern: pattern,
                       allowFiles: allowFiles, allowLine: allowLine)
    }

    private func violations(
        in files: [URL], pattern: String, allowFiles: Set<String>,
        allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var hits: [String] = []
        for file in files {
            let rel = relative(file)
            guard !allowFiles.contains(rel) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                let range = NSRange(s.startIndex..., in: s)
                guard regex.firstMatch(in: s, range: range) != nil else { continue }
                if let allowLine, allowLine(s) { continue }
                hits.append("\(rel):\(index + 1): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        return hits
    }

    /// Hardcoded gm binary paths are wrong under sandbox (they'd drive the
    /// prod db) and redundant under the PATH shim. Exempt: bootstrap flows
    /// that run before the shim exists, permission-grant literals, and
    /// user-facing remediation messages that state where the binary lives.
    func testNoHardcodedGmBinaryPaths() throws {
        let hits = try violations(
            pattern: #"gmcc/bin/gm"#,
            allowFiles: [
                "commands/gm_init.md",              // bootstrap sequence + grant literals
                "commands/gmcc_daemon.md",          // remediation/success message text
                "commands/refresh_daemon_state.md", // staleness stat + message text
                "skills/gmcc_boot/SKILL.md",        // gm-missing remediation block
                "skills/gmcc_cleanup_system/SKILL.md", // grant literal it audits
            ],
            allowLine: { $0.contains("local_sandbox") })  // sandbox launchers are deliberately absolute
        XCTAssertEqual(hits, [], "hardcoded gm binary path in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The retired session env family no longer exists — an unswept
    /// `$GMCC_SESSION_PATH` expands to EMPTY in a shell. Exempt: the gmcc
    /// skill's explicit retirement notice.
    func testNoRetiredEnvNames() throws {
        let hits = try violations(
            pattern: #"GMCC_PROJECTS|GMCC_PROJECT_PATH|GMCC_INSTANCE_PATH|GMCC_SESSION_PATH|GMCC_KBITE"#,
            allowFiles: [
                "skills/gmcc/SKILL.md",             // the retirement notice itself
            ])
        XCTAssertEqual(hits, [], "retired env var referenced in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The old expansion is retired everywhere; DopeVocabulary is canonical.
    func testNoRetiredDopeExpansion() throws {
        let hits = try violations(
            pattern: NSRegularExpression.escapedPattern(for: DopeVocabulary.retiredAcronym),
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired DOPE expansion in docs:\n" + hits.joined(separator: "\n"))
    }

    /// Nothing may recreate the ~/.zshrc gmcc env block. Exempt: the two
    /// places that talk ABOUT deleting it.
    func testZshrcBlockMarkerOnlyInCleanupDocs() throws {
        let hits = try violations(
            pattern: #">>> gmcc env >>>"#,
            allowFiles: [
                "commands/gm_init.md",                 // "check it does NOT exist" + pointer
                "skills/gmcc_cleanup_system/SKILL.md", // the deletion remedy
            ])
        XCTAssertEqual(hits, [], "zshrc gmcc block referenced outside cleanup docs:\n" + hits.joined(separator: "\n"))
    }

    /// m0025 retirements: the pre_architecture briefing step (the care
    /// package replaced it), the clarification summary text fields, the
    /// clarify ask/category verbs, the merged exploration_key_file table,
    /// and the finalize→prompt.goal copy. A doc resurrecting any of these
    /// re-teaches a retired machine. Exempt: nothing — history lives in
    /// migration comments (Swift), not docs.
    func testNoRetiredWorkflowConcepts() throws {
        let hits = try violations(
            pattern: #"pre_architecture|refined_goal|refined_detail|backstory_note|clarify ask|--category goal|exploration_key_file|copies refined|finalize copies"#,
            allowFiles: [])
        XCTAssertEqual(
            hits, [],
            "retired m0025 workflow concept in docs:\n" + hits.joined(separator: "\n"))
    }

    /// --adopt is boot-sync-only; a bot tier instructing agents to use it
    /// would silently discard db-side dope work.
    func testAdoptFlagAbsentFromBotTiers() throws {
        for name in ["commands/gm_bot.md", "commands/gm_bot_rpi.md", "commands/gm_bot_team.md"] {
            let url = pluginRoot.appendingPathComponent(name)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.contains("--adopt"), "\(name) must not mention --adopt")
        }
    }

    /// m0013 renamed the tier to SESSION_INSTANCE. Docs AND sources: the tier
    /// name reaches users through the cheatsheet and `gm dope --help`, not
    /// just through markdown.
    func testNoRetiredSessionBaseTier() throws {
        let pattern = #"\bSESSION_BASE\b"#
        // The real flag is named --clone-from-session-base; it is not a tier
        // reference and must survive this sweep.
        let allowLine: (String) -> Bool = { $0.lowercased().contains("session-base") }
        var hits = try violations(pattern: pattern, allowFiles: [], allowLine: allowLine)
        hits += try violations(
            in: try swiftFiles(), pattern: pattern,
            allowFiles: [
                // The m0012/m0013 literals and history — SESSION_BASE is the
                // stored value these migrations read and rewrite.
                "daemon/Sources/GMCCDaemonKit/Database/Migrations.swift",
                // The legacy decode alias, so an old file still parses. The
                // file self-updates on its next write.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeLevel.swift",
                // Documents the retired spelling it is tolerant of.
                "daemon/Sources/GMCCDaemonKit/Protocol/Rows.swift",
            ],
            allowLine: allowLine)
        XCTAssertEqual(hits, [], "retired SESSION_BASE tier referenced:\n" + hits.joined(separator: "\n"))
    }

    /// The dope tree moved to `{instance_root}/.gmcc` — `.gmcc/dope` is the
    /// retired layout. A stale path here sent gm doctor's drift check at a
    /// file that never exists, so the finding silently never fired.
    func testNoRetiredDopeDirectory() throws {
        let pattern = #"\.gmcc/dope"#
        var hits = try violations(
            pattern: pattern,
            allowFiles: [
                // The layout reference itself — it names the retired path in
                // order to tell the reader it is retired.
                "skills/gmcc/ref/doped_files.md",
            ])
        hits += try violations(
            in: try swiftFiles(), pattern: pattern,
            allowFiles: [
                // Defines legacyDopeDirectoryName / legacyMainFileName.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeDocument.swift",
                // legacyDopeRoot + the note on why the old layout could be
                // swapped wholesale and the new one cannot.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeRepoSandbox.swift",
                // Probes the retired tree on purpose, to warn about a stale
                // checkout and tell the user how to republish it.
                "daemon/Sources/GMCCDaemonKit/Dope/DopeBootSync.swift",
            ])
        XCTAssertEqual(hits, [], "retired .gmcc/dope path referenced:\n" + hits.joined(separator: "\n"))
    }

    /// m0012 renamed the dope domain-* verbs to persistence-*. A doc that
    /// still names the old family hands an agent an unknown subcommand.
    func testNoRetiredDopeVerbNames() throws {
        let hits = try violations(
            pattern: #"dope (domain-(add|update|delete)|\{domain,)"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired dope domain-* verb in docs:\n" + hits.joined(separator: "\n"))
    }

    /// The pen-down cleanup's premise killer: no doc may ever again claim a
    /// subagent runs in a "read-only sandbox" — that fiction is what kept the
    /// rpi transcription tax alive for months.
    func testNoReadOnlySandboxPremise() throws {
        let hits = try violations(pattern: #"read-only sandbox"#, allowFiles: [])
        XCTAssertEqual(hits, [], "the retired read-only-sandbox premise resurfaced:\n" + hits.joined(separator: "\n"))
    }

    /// The verbatim-paste mandate is retired: teammates get the compact core
    /// from SessionStart and Task subagents get the SubagentStart stub. A doc
    /// may SAY "never paste cheatsheets" — what it may not do is mandate
    /// pasting the sheet's verbatim output into spawn prompts again.
    func testNoCheatsheetPasteMandate() throws {
        let hits = try violations(
            pattern: #"verbatim output of\s+`?gm cheatsheet"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "a cheatsheet paste mandate resurfaced:\n" + hits.joined(separator: "\n"))
    }

    /// gmcc_daemon/SKILL.md is a ROUTING skill: it says which door to knock on,
    /// never what the signatures behind that door are. Duplicated signatures
    /// and version literals are what let it drift; the pen tools' own schemas
    /// and `gmcc_hook verbs --json` are the authority it must point at instead.
    func testDaemonSkillCarriesNoVersionLiteralsOrSignatures() throws {
        let skill = pluginRoot.appendingPathComponent("skills/gmcc_daemon/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        XCTAssertLessThan(
            text.utf8.count, 8192,
            "gmcc_daemon/SKILL.md outgrew its routing-skill diet")
        for pattern in [#"wire (protocol )?v\d"#, #"schema m\d{4}"#] {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(
                regex.firstMatch(in: text, range: range),
                "gmcc_daemon/SKILL.md carries a version literal (pattern \(pattern)) — the live catalogue is the only authority")
        }
        XCTAssertTrue(
            text.contains("gmcc_hook verbs --json"),
            "gmcc_daemon/SKILL.md must route MessageType questions to gmcc_hook verbs --json")
    }

    /// The retired identity-file agent system: nothing may point agents at
    /// prompts/*.prompt.md role files or output-styles/ again — identity
    /// lives in plugins/gmcc/agents/ defs now. The two crunch/maw prompts
    /// are the deliberate survivors.
    func testNoRetiredAgentIdentitySurfaces() throws {
        // Three faces of the same retired system (review finding 7fbaca71
        // widened this: the original pattern needed the .prompt.md suffix,
        // which let a 254-line skill canonizing the gmcc:agent:{name}
        // invocation syntax slip through): the role prompt files, the
        // output-styles fragments, the skills/gmcc_agent skill, and the
        // gmcc:agent:{...} invocation form itself. The crunch/maw prompts
        // (gmcc_agent_kbite_crunch_chew / gmcc_agent_maw_web_fetch) are the
        // deliberate survivors and match none of these.
        let hits = try violations(
            pattern: #"(gmcc_agent_(code_explorer|code_architect|code_quality_reviewer|finding_reranker)\.prompt\.md|output-styles/|skills/gmcc_agent\b|gmcc:agent:\{)"#,
            allowFiles: [])
        XCTAssertEqual(hits, [], "retired agent identity surface referenced in docs:\n" + hits.joined(separator: "\n"))
    }

    /// Two agents were retired by the clarifier merge: `finding-reranker`
    /// (its rank pass folded into the clarifier's single reader) and `ques`
    /// (renamed to `clarifier`, and the proper-name/persona framing dropped —
    /// SKILL.md establishes exactly one persona, the GMB). A doc or a def
    /// naming either hands the primary a `Task` subagent_type that does not
    /// resolve, which fails the phase rather than degrading it.
    ///
    /// Walks the doc tree, the agent defs AND `daemon/Sources`: the retired
    /// names reached callers through CLI `--help` abstracts and the compiled
    /// instruction blocks as much as through markdown.
    ///
    /// `The Ques` / `the-ques` are bounded so `The Question` and
    /// `--clone-from-the-quest…`-shaped words cannot false-positive, and
    /// `gmcc:ques` is bounded so `gmcc:clarifier` reads clean.
    func testNoRetiredClarifierAgentNames() throws {
        let pattern = #"finding-reranker|gmcc:ques\b|\bThe Ques\b|\bthe-ques\b"#
        var hits = try violations(pattern: pattern, allowFiles: [])
        hits += try violations(in: try agentFiles(), pattern: pattern, allowFiles: [])
        hits += try violations(in: try swiftFiles(), pattern: pattern, allowFiles: [])
        XCTAssertEqual(
            hits, [],
            "retired clarifier-merge agent name referenced:\n" + hits.joined(separator: "\n"))
    }

    // MARK: - Hook / launcher contract
    //
    // WHY THIS LIVES IN A TEST AND NOT IN A CHECKLIST. Every other surface in
    // this plugin fails loudly and locally: a bad skill is a bad answer, a bad
    // verb is an error return. A bad `hooks.json` entry is different in kind —
    // the harness runs it on a turn boundary in EVERY session, GMCC's or not,
    // so a syntax error or a renamed script is a global stall with no obvious
    // culprit. That is precisely the shape of risk the CheatsheetTests /
    // VerbRegistryTests precedent exists for, and it is the one place it had
    // not been applied.
    //
    // These assert SHAPE, never a fixed roster of hook events. Which events
    // the plugin subscribes to is a live design question; that every command
    // it declares resolves to a real, executable, syntactically valid script
    // is not.

    private var scriptsDir: URL {
        pluginRoot.appendingPathComponent("scripts", isDirectory: true)
    }

    /// Every `*.sh` the plugin ships.
    private func shellScripts() throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: scriptsDir, includingPropertiesForKeys: nil)
        let out = contents.filter { $0.pathExtension == "sh" }.sorted { $0.path < $1.path }
        XCTAssertGreaterThan(out.count, 4, "scripts walk looks broken: \(scriptsDir.path)")
        return out
    }

    /// Parse one plugin-root-relative JSON file into a dictionary. Returns nil
    /// when the file is absent; FAILS when it is present and unparseable —
    /// "present but malformed" is the wedge this whole section is about.
    private func jsonObject(_ relativePath: String) -> [String: Any]? {
        let url = pluginRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            XCTFail("\(relativePath) is unreadable")
            return nil
        }
        let parsed = try? JSONSerialization.jsonObject(with: data)
        guard let object = parsed as? [String: Any] else {
            XCTFail("\(relativePath) is not a JSON object — the harness will refuse to load it")
            return nil
        }
        return object
    }

    /// `bash -n` one script. nil = clean (or no bash to test with, on a host
    /// that has none — the test degrades rather than lying).
    private func bashSyntaxError(_ url: URL) -> String? {
        let bash = "/bin/bash"
        guard FileManager.default.isExecutableFile(atPath: bash) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bash)
        process.arguments = ["-n", url.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        do { try process.run() } catch { return nil }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "bash -n exited \(process.terminationStatus)" : text
    }

    /// Every `scripts/<file>` a command string names. A command may be a bare
    /// path (hooks.json) or a shell snippet (settings.json's launcher), so the
    /// reference is matched rather than the whole string parsed.
    private func referencedScripts(in command: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"scripts/([A-Za-z0-9_.\-]+)"#)
        let range = NSRange(command.startIndex..., in: command)
        return regex.matches(in: command, range: range).compactMap { match in
            Range(match.range(at: 1), in: command).map { String(command[$0]) }
        }
    }

    /// The shared assertion behind all three manifests: the script a command
    /// names exists, is executable, and parses.
    private func assertScriptIsLaunchable(_ name: String, from source: String) {
        let url = scriptsDir.appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            XCTFail("\(source) launches scripts/\(name), which does not exist")
            return
        }
        XCTAssertTrue(
            fm.isExecutableFile(atPath: url.path),
            "\(source) launches scripts/\(name), which is not executable — the harness gets exit 126")
        if url.pathExtension == "sh", let error = bashSyntaxError(url) {
            XCTFail("\(source) launches scripts/\(name), which fails `bash -n`:\n\(error)")
        }
    }

    /// Nothing in `scripts/` may be syntactically broken, whether or not a
    /// manifest currently points at it — a script is wired up long after it is
    /// written, and a parse error found at wiring time is found in production.
    func testEveryShippedShellScriptParses() throws {
        for script in try shellScripts() {
            if let error = bashSyntaxError(script) {
                XCTFail("scripts/\(script.lastPathComponent) fails `bash -n`:\n\(error)")
            }
        }
    }

    /// `hooks.json` is well-formed and every command it declares is
    /// launchable. Walks whatever events are present — the subscription list
    /// is a design decision, the resolvability of what it declares is not.
    func testHookManifestIsWellFormedAndEveryCommandLaunches() throws {
        guard let root = jsonObject("hooks/hooks.json") else {
            XCTFail("plugins/gmcc/hooks/hooks.json is missing")
            return
        }
        guard let events = root["hooks"] as? [String: Any] else {
            XCTFail("hooks.json has no top-level `hooks` object")
            return
        }
        XCTAssertFalse(events.isEmpty, "hooks.json subscribes to no events at all")

        var commandCount = 0
        for (event, value) in events {
            guard let groups = value as? [[String: Any]] else {
                XCTFail("hooks.json `\(event)` is not an array of matcher groups")
                continue
            }
            XCTAssertFalse(groups.isEmpty, "hooks.json `\(event)` declares no groups")
            for (groupIndex, group) in groups.enumerated() {
                let where_ = "hooks.json \(event)[\(groupIndex)]"
                if let matcher = group["matcher"] {
                    XCTAssertTrue(
                        matcher is String,
                        "\(where_) has a non-string `matcher` — the harness compiles it as a regex")
                }
                guard let entries = group["hooks"] as? [[String: Any]] else {
                    XCTFail("\(where_) has no `hooks` array")
                    continue
                }
                XCTAssertFalse(entries.isEmpty, "\(where_) declares an empty `hooks` array")
                for entry in entries {
                    commandCount += 1
                    XCTAssertEqual(
                        entry["type"] as? String, "command",
                        "\(where_) declares a hook that is not type `command`")
                    if let async = entry["async"] {
                        XCTAssertTrue(async is Bool, "\(where_) has a non-boolean `async`")
                    }
                    guard let command = entry["command"] as? String, !command.isEmpty else {
                        XCTFail("\(where_) declares a hook with no `command` string")
                        continue
                    }
                    // The one spelling the harness actually expands. A bare
                    // relative path here runs as `/scripts/...` and exits 127
                    // on every single turn.
                    XCTAssertTrue(
                        command.contains("${CLAUDE_PLUGIN_ROOT}/scripts/"),
                        "\(where_) command does not go through ${CLAUDE_PLUGIN_ROOT}/scripts/: \(command)")
                    let referenced = try referencedScripts(in: command)
                    XCTAssertFalse(
                        referenced.isEmpty, "\(where_) command names no script: \(command)")
                    for name in referenced {
                        assertScriptIsLaunchable(name, from: where_)
                    }
                }
            }
        }
        XCTAssertGreaterThan(commandCount, 2, "hooks.json walk looks broken")
    }

    /// A hook script must locate `gm` FROM THE FILESYSTEM and no-op when it is
    /// not there. Nothing a hook needs may come out of the inherited
    /// environment: a hook runs with whatever the harness hands it, which is
    /// not what `gm context env` provisioned the session with, so a gate or a
    /// lookup keyed on either one is a hook that stops firing and never says
    /// so. That failure is why this prompt exists.
    ///
    /// SessionStart is exempt by definition — it is the event that performs
    /// the boot, so it cannot require the boot to have happened, and it is the
    /// one script that legitimately exports the GMCC_* names.
    ///
    /// THE BANS ARE THE LOAD-BEARING HALF. The PRESENT assertions describe a
    /// shape that would survive someone re-adding `[ -z "$GMCC_BOOTED" ] &&
    /// exit 0` above it; the ABSENT list is what refuses the re-add. Each
    /// banned spelling failed for the SAME reason — it consults inherited
    /// state — and they were found one at a time, months apart, which is
    /// exactly why the list is enforced rather than remembered.
    ///
    /// Not asserted here, because it is not a shell property: a hook that
    /// WRITES is additionally refused daemon-side unless the payload's
    /// session_id has a row in the claude-session binding.
    func testNonBootHookScriptsResolveGmWithoutInheritedEnv() throws {
        /// A spelling that reads inherited state, and why it is refused. The
        /// message names the reason so the next author reads an argument
        /// rather than a rule.
        let banned: [(needle: String, why: String)] = [
            ("GMCC_BOOTED",
             "the session env does not survive into a hook process, so this gate silently disables the hook"),
            ("command -v gm",
             "the binary is on the session PATH, not the hook's — this resolves to nothing and exits 0 forever"),
            ("command -v gmcc_hook",
             "the same inherited-PATH failure under the new name — resolve from the script's own location instead"),
            ("command -v jq",
             "the same inherited-PATH failure one dependency over; a tool a hook needs is found on disk or not needed at all"),
        ]
        guard let root = jsonObject("hooks/hooks.json"),
              let events = root["hooks"] as? [String: Any]
        else { return }
        var checked = 0
        for (event, value) in events where event != "SessionStart" {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                for entry in (group["hooks"] as? [[String: Any]]) ?? [] {
                    guard let command = entry["command"] as? String else { continue }
                    for name in try referencedScripts(in: command) {
                        let url = scriptsDir.appendingPathComponent(name)
                        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                        checked += 1

                        // PRESENT — the two halves of the resolution. The
                        // script's own location anchors it, the marker walk
                        // retargets a sandbox snapshot, and `$HOME/gmcc` is
                        // the default when there is no marker.
                        for (needle, what) in [
                            (#"dirname"#, "resolve its binary from its own script location"),
                            (#".gmcc_sandbox"#, "walk up for a sandbox marker, or a snapshot's hooks write the prod db"),
                            (#"$HOME/gmcc"#, "fall back to the default runtime root"),
                        ] {
                            XCTAssertTrue(
                                text.contains(needle),
                                """
                                scripts/\(name) runs on \(event) but contains no `\(needle)` — \
                                it cannot \(what) without reading the environment.
                                """)
                        }
                        XCTAssertTrue(
                            text.contains(#"[ -x "$HOOK_BIN" ] || exit 0"#),
                            """
                            scripts/\(name) runs on \(event) but carries no \
                            `[ -x "$HOOK_BIN" ] || exit 0` — with no binary on disk it must \
                            exit 0 in silence, never block a tool call or wedge a spawn.
                            """)

                        // ABSENT — the re-add guard.
                        for (needle, why) in banned {
                            XCTAssertFalse(
                                text.contains(needle),
                                """
                                scripts/\(name) runs on \(event) and contains `\(needle)`: \(why). \
                                Resolve what the hook needs from the filesystem instead.
                                """)
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1, "hooks.json walk found no non-SessionStart scripts")
    }

    /// A plugin `settings.json` may carry ONLY the keys the harness reads. An
    /// unsupported key is not ignored politely everywhere, and this file ships
    /// to every install.
    func testPluginSettingsCarriesOnlySupportedKeys() throws {
        guard let root = jsonObject("settings.json") else { return }
        // The two keys a PLUGIN's settings.json is allowed to contribute.
        let supported: Set<String> = ["agent", "subagentStatusLine"]
        let unsupported = Set(root.keys).subtracting(supported).sorted()
        XCTAssertEqual(
            unsupported, [],
            "plugins/gmcc/settings.json carries unsupported key(s) \(unsupported) — a plugin may set only \(supported.sorted())")

        if let statusLine = root["subagentStatusLine"] {
            guard let entry = statusLine as? [String: Any] else {
                XCTFail("settings.json subagentStatusLine is not an object")
                return
            }
            XCTAssertEqual(
                entry["type"] as? String, "command",
                "settings.json subagentStatusLine is not type `command`")
            guard let command = entry["command"] as? String, !command.isEmpty else {
                XCTFail("settings.json subagentStatusLine has no `command` string")
                return
            }
            let referenced = try referencedScripts(in: command)
            XCTAssertFalse(
                referenced.isEmpty,
                "settings.json subagentStatusLine names no script: \(command)")
            for name in referenced {
                assertScriptIsLaunchable(name, from: "settings.json subagentStatusLine")
            }
        }
    }

    /// `.mcp.json` is the pen's front door — it is loaded at startup, so a
    /// broken command string here is a startup failure, not a lazy one.
    func testMcpManifestIsWellFormedAndEveryServerLaunches() throws {
        guard let root = jsonObject(".mcp.json") else {
            XCTFail("plugins/gmcc/.mcp.json is missing")
            return
        }
        guard let servers = root["mcpServers"] as? [String: Any], !servers.isEmpty else {
            XCTFail(".mcp.json has no non-empty `mcpServers` object")
            return
        }
        for (name, value) in servers {
            guard let server = value as? [String: Any] else {
                XCTFail(".mcp.json server `\(name)` is not an object")
                continue
            }
            if let alwaysLoad = server["alwaysLoad"] {
                XCTAssertTrue(
                    alwaysLoad is Bool, ".mcp.json server `\(name)` has a non-boolean `alwaysLoad`")
            }
            guard let command = server["command"] as? String, !command.isEmpty else {
                XCTFail(".mcp.json server `\(name)` has no `command` string")
                continue
            }
            for script in try referencedScripts(in: command) {
                assertScriptIsLaunchable(script, from: ".mcp.json server `\(name)`")
            }
        }
    }
}
