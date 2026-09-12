import XCTest
@testable import GMCCDaemonKit

/// The bot workflow registry's drift guards (the CheatsheetTests precedent
/// scaled to the state machine): every (variant, phase) pair must carry
/// instruction text, every phase graph must be well-formed, and the MCP pen
/// roster must stay in lockstep with the agent defs that name its tools —
/// a naming mistake here bricks every agent pen under the all-or-nothing
/// MCP migration.
final class WorkflowSpecTests: XCTestCase {

    // MARK: - Phase graphs

    func testEveryVariantPhaseHasInstructions() {
        for variant in BotVariant.allCases {
            let phases = WorkflowSpec.phases(for: variant)
            XCTAssertGreaterThan(phases.count, 5, "\(variant) graph looks broken")
            XCTAssertEqual(phases.first, .briefing, "\(variant) must start at briefing")
            XCTAssertEqual(phases.last, .done, "\(variant) must end at done")
            XCTAssertEqual(
                phases.count, Set(phases).count, "\(variant) graph repeats a phase")
            for phase in phases {
                let text = WorkflowSpec.instructions(variant: variant, phase: phase)
                XCTAssertFalse(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "(\(variant), \(phase)) has no instruction text")
            }
        }
    }

    func testExpectedExplorationAgentsAreWellFormed() {
        for variant in BotVariant.allCases {
            let agents = WorkflowSpec.expectedExplorationAgents(for: variant)
            XCTAssertFalse(agents.isEmpty, "\(variant) expects no exploration agents")
            // The synthesis row is the SEAL — never an expected worker.
            XCTAssertFalse(
                agents.contains(.synthesis),
                "\(variant) lists synthesis as an expected agent")
        }
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .team).count, 4)
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .bot), [.general])
        XCTAssertEqual(WorkflowSpec.expectedExplorationAgents(for: .rpi), [.general])
    }

    func testVariantGraphShapes() {
        // Only team runs the options flow; bot skips the care package.
        XCTAssertFalse(WorkflowSpec.phases(for: .bot).contains(.carePackage))
        XCTAssertFalse(WorkflowSpec.phases(for: .bot).contains(.archOptions))
        XCTAssertTrue(WorkflowSpec.phases(for: .rpi).contains(.carePackage))
        XCTAssertFalse(WorkflowSpec.phases(for: .rpi).contains(.archOptions))
        XCTAssertTrue(WorkflowSpec.phases(for: .team).contains(.archOptions))
    }

    // MARK: - MCP pen roster
    //
    // WHAT USED TO BE HERE, AND WHY IT IS GONE.
    //
    // Three things were deleted in the commit that added VerbRegistry:
    //
    //   1. A forbidden-SUBSTRING loop over ["rank","decide","set_status",
    //      "finalize","approve"] asserting none of them appeared in a tool
    //      NAME. That is a spelling check standing in for an authorization
    //      check — it could not see a door, only a word, and it is exactly
    //      why `gm explore rank` could be handed to an agent in prose while
    //      the test stayed green. Its replacement is VerbRegistryTests, which
    //      asserts the decision the daemon actually makes.
    //   2. A hardcoded 19-name expected roster, which had to be hand-edited
    //      every time the pen grew a tool.
    //   3. mcpToolNames(), which scraped `name: "` line prefixes out of
    //      gmcc_mcp/main.swift's SOURCE TEXT — brittle in both directions
    //      (any params literal formatted that way would have been counted as
    //      a tool).
    //
    // The registry is the roster now. VerbRegistry.penToolNames is what
    // gmcc_mcp serves, what `gm verbs --json` prints, and what agent defs may
    // name — and the parity below is BIDIRECTIONAL, so neither side can grow
    // a tool the other has not heard of.

    /// plugins/gmcc/, located from this file (the DocsContractTests trick).
    private var pluginRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRegistryDeclaresACoherentPenSurface() {
        let roster = VerbRegistry.penToolNames
        XCTAssertGreaterThan(roster.count, 12, "the registry declares almost no pen surface")
        for tool in roster {
            XCTAssertEqual(
                tool, tool.lowercased(),
                "pen tool '\(tool)' is not snake_case — MCP tool names are mcp__plugin_gmcc_pen__<tool>")
            XCTAssertFalse(tool.contains(" "), "pen tool '\(tool)' contains a space")
        }
    }

    /// The tools gmcc_mcp actually serves, read off the `Tool(` literals. The
    /// read is anchored on `Tool(` rather than on a bare `name: "` line prefix,
    /// so a params tuple can never be mistaken for a tool.
    private func servedPenTools() throws -> [String] {
        // EVERY file in the target, not just main.swift. The roster outgrew one
        // file when the fast path and the primary doors arrived, and a scan
        // anchored on a single filename would have reported them as absent while
        // the binary served them — a parity check that reads the wrong half of
        // the surface is worse than none.
        let dir = pluginRoot.appendingPathComponent("daemon/Sources/gmcc_mcp")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no gmcc_mcp sources found — the roster read is broken")
        let pattern = try NSRegularExpression(pattern: #"\bTool\(\s*\n\s*name:\s*"([a-z0-9_]+)""#)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            found += matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            }
        }
        return found
    }

    /// FULL PARITY, both directions. Roster → registry catches an orphan tool
    /// the door has made no role decision about. Registry → roster catches the
    /// worse one: a VerbSpec that promises a pen replacement no binary serves,
    /// which is a `gm verbs` deny reason pointing at a tool that does not
    /// exist — the guard tells an agent to use something it cannot call.
    func testPenRosterAndRegistryAreTheSameSet() throws {
        let served = try servedPenTools()
        XCTAssertGreaterThan(served.count, 12, "tool roster read looks broken")
        XCTAssertEqual(served.count, Set(served).count, "duplicate MCP tool names")
        let registry = VerbRegistry.penToolNames
        for tool in served {
            XCTAssertTrue(
                registry.contains(tool),
                """
                gmcc_mcp serves '\(tool)' but VerbRegistry has no row for it. \
                Add a VerbSpec (pen: "\(tool)") — or, if it composes several \
                verbs, a VerbRegistry.compositePenTools entry.
                """)
        }
        for tool in registry.sorted() {
            XCTAssertTrue(
                served.contains(tool),
                """
                VerbRegistry declares pen tool '\(tool)' but gmcc_mcp does not \
                serve it. Add the Tool literal, or drop the `pen:` from its \
                VerbSpec — a promised-but-absent tool is what a deny reason \
                would name.
                """)
        }
    }

    // MARK: - Instruction content
    //
    // The teeth. bot_next is a pass-through: this prose IS what an agent is
    // handed, so a block that spells a `gm` write is the CLI being handed to
    // someone who was told not to use it. Presence-only assertions let that
    // ship for as long as the file has existed.

    /// Does `text` name this invocation as a command (not as a prefix of a
    /// longer one)?
    private func names(_ invocation: String, in text: String) -> Bool {
        var search = text[...]
        while let found = search.range(of: invocation) {
            let after = found.upperBound
            let boundary = after == text.endIndex
                || !(text[after].isLetter || text[after].isNumber || text[after] == "-")
            if boundary { return true }
            search = text[after...]
        }
        return false
    }

    /// NO INSTRUCTION BLOCK MAY NAME A `gm` WRITE VERB THAT HAS A PEN
    /// REPLACEMENT. What survives is exactly the set VerbRegistry justifies:
    /// the primary's four gate doors (no pen tool by definition — an agent is
    /// refused them at the daemon), and writes with no pen tool at all, which
    /// the primary alone can make.
    func testInstructionsNameThePenForEveryWriteThatHasOne() {
        let writesWithAPen = VerbRegistry.all.filter {
            $0.penTool != nil && $0.role != .read && !$0.gmInvocation.isEmpty
        }
        XCTAssertGreaterThan(writesWithAPen.count, 5, "registry read looks broken")
        for variant in BotVariant.allCases {
            for phase in WorkflowSpec.phases(for: variant) {
                let text = WorkflowSpec.instructions(variant: variant, phase: phase)
                for spec in writesWithAPen where names(spec.gmInvocation, in: text) {
                    XCTFail("""
                        (\(variant), \(phase)) instructs `\(spec.gmInvocation)`, but that \
                        write has a pen tool: mcp__plugin_gmcc_pen__\(spec.penTool ?? "?"). \
                        This text is served to agents through bot_next — naming the CLI \
                        here is how an agent ends up writing from Bash.
                        """)
                }
            }
        }
    }

    // MARK: - Agent-facing prose
    //
    // `WorkflowSpec.instructions` is not the only text that spawns agents.
    // `Task(subagent_type:)` prompts come from `agents/`, the tier playbooks
    // from `commands/`, and the reference prose every one of them reads from
    // `skills/`. An assertion that reaches only the instruction blocks is an
    // assertion over the one file that was already cleaned by hand; the drift
    // it exists to end lives in the other three surfaces, where nothing was
    // watching. So the same registry-driven rule is applied to the markdown.
    //
    // THE EXEMPTION IS A MARKER IN THE PROSE, NOT A FILENAME. A file
    // allowlist rots the moment someone adds a file — which is precisely the
    // failure mode being fixed — and it exempts a whole document when the
    // thing that deserves exemption is one sentence. The rule this change
    // adopted is narrow: the CLI is not an acceptable write path *where a pen
    // tool exists AND the instruction is addressed to a spawned agent*. A
    // `gm` write addressed to the primary or to the human is legitimate, and
    // the author says so in the sentence, in the words below. The marker
    // travels with the sentence it justifies.

    /// The literal an author writes to declare that a nearby `gm` write is
    /// the primary's or the human's, not something a spawned agent is being
    /// told to run. Chosen to read as ordinary prose so it documents itself
    /// to a human reader, and to be specific enough that it cannot appear by
    /// accident.
    private static let primaryWriteMarker = "not an agent write path"

    /// Everything a spawned agent or a tier playbook can read: the agent
    /// defs, the tier commands, the reference skills, the prompt fragments.
    private func agentFacingDocs() throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in ["agents", "commands", "skills", "prompts", "output-styles"] {
            let root = pluginRoot.appendingPathComponent(dir, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "md" { out.append(url) }
            }
        }
        XCTAssertGreaterThan(
            out.count, 20, "agent-facing doc walk looks broken: \(pluginRoot.path)")
        return out
    }

    /// Which lines the marker covers. Scope is deliberately TIGHT — one line
    /// of reach, not a section — so a marker can never silently bless an
    /// agent-addressed line somebody appends underneath it later:
    ///
    ///   * a line carrying the marker itself,
    ///   * the line immediately after it,
    ///   * a fenced code block whose opening fence is that following line —
    ///     the only way to justify a multi-line CLI example, since a comment
    ///     inside the fence would become part of the command.
    private func markedLines(_ lines: [String]) -> [Bool] {
        let marker = Self.primaryWriteMarker
        var covered = [Bool](repeating: false, count: lines.count)
        var inFence = false
        var fenceCovered = false
        for (index, line) in lines.enumerated() {
            let previousMarks = index > 0 && lines[index - 1].contains(marker)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inFence {
                    covered[index] = fenceCovered
                    inFence = false
                    fenceCovered = false
                } else {
                    inFence = true
                    fenceCovered = previousMarks
                    covered[index] = fenceCovered
                }
                continue
            }
            covered[index] = inFence ? fenceCovered : (line.contains(marker) || previousMarks)
        }
        return covered
    }

    private func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: pluginRoot.path + "/", with: "")
    }

    /// THE SAME RULE AS THE INSTRUCTION BLOCKS, APPLIED WHERE AGENTS ARE
    /// ACTUALLY SPAWNED. For every registry row that is a write and has a pen
    /// replacement, no agent-facing markdown may name its `gm` invocation
    /// unless the sentence explicitly marks it as the primary's or the
    /// human's.
    ///
    /// What is legitimate and therefore never reaches this loop: the four
    /// primary doors (no `penTool` by definition) and every read verb, both
    /// filtered out below; and `gm` writes with no pen tool at all, which the
    /// primary alone can make.
    ///
    /// EVERY SPELLING IS CHECKED, canonical and alias alike. `gm bot summary`
    /// teaches `gm explore open` just as effectively under a friendlier name,
    /// and `gmAliases` exists precisely because the CLI ships several wrappers
    /// over one verb — a rule that saw only the canonical form would be a rule
    /// the friendliest spelling walks straight through.
    func testAgentFacingDocsNameThePenForEveryWriteThatHasOne() throws {
        let writesWithAPen = VerbRegistry.all.filter {
            $0.penTool != nil && $0.role != .read && !$0.gmInvocation.isEmpty
        }
        XCTAssertGreaterThan(writesWithAPen.count, 5, "registry read looks broken")

        // The ONE file allowlist, and it is the retirement-notice exemption
        // DocsContractTests already carries: SKILL.md states the GMB's own
        // baseline behaviour to the primary, outside any workflow row.
        let allowFiles: Set<String> = ["skills/gmcc/SKILL.md"]

        var hits: [String] = []
        for url in try agentFacingDocs() {
            let rel = relative(url)
            guard !allowFiles.contains(rel) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            let covered = markedLines(lines)
            for (index, line) in lines.enumerated() where !covered[index] {
                for spec in writesWithAPen {
                    for invocation in spec.gmInvocations where names(invocation, in: line) {
                        hits.append("""
                            \(rel):\(index + 1): `\(invocation)` has a pen tool \
                            (mcp__plugin_gmcc_pen__\(spec.penTool ?? "?")) — name the pen tool, or, \
                            if this sentence addresses the primary or the human, say so with the \
                            words "\(Self.primaryWriteMarker)" on this line or the one above it.
                            """)
                    }
                }
            }
        }
        XCTAssertEqual(
            hits, [],
            "agent-facing doc teaches a pen-replaced `gm` write:\n" + hits.joined(separator: "\n"))
    }

    /// THE FOUR THAT ADVANCE THE MACHINE must each carry a pen tool and be
    /// named in some instruction block, or the primary has no documented way to
    /// move the workflow forward.
    ///
    /// It is a REACHABILITY test, not an authorization one: nothing refuses a
    /// caller for using these. What reserves them for the primary is
    /// methodology — cross-agent calibration and the choice among options
    /// belong to one reader — and that is carried by the pen sheet and by each
    /// agent's own tool list.
    func testPrimaryPenToolsAreServedAndNamedInTheInstructions() {
        let primaryTools = VerbRegistry.primaryPenTools
        XCTAssertEqual(primaryTools.count, 4, "the machine advances through exactly four tools")
        var everyBlock = ""
        for variant in BotVariant.allCases {
            for phase in WorkflowSpec.phases(for: variant) {
                everyBlock += WorkflowSpec.instructions(variant: variant, phase: phase) + "\n"
            }
        }
        for pen in primaryTools.sorted() {
            XCTAssertTrue(
                VerbRegistry.penToolNames.contains(pen),
                "\(pen) is named as the primary's call but no VerbSpec serves it")
            XCTAssertTrue(
                names("mcp__plugin_gmcc_pen__" + pen, in: everyBlock),
                "no instruction block tells the primary to call `\(pen)`")
        }
    }

    /// Every `mcp__plugin_gmcc_pen__<tool>` named in instruction prose must
    /// exist in the registry (and therefore on the roster, by the parity test
    /// above). A typo here is an agent reaching for a tool it does not have.
    func testInstructionsOnlyNameRealPenTools() {
        let prefix = "mcp__plugin_gmcc_pen__"
        let roster = VerbRegistry.penToolNames
        var named = 0
        for variant in BotVariant.allCases {
            for phase in WorkflowSpec.phases(for: variant) {
                let text = WorkflowSpec.instructions(variant: variant, phase: phase)
                for token in text.split(whereSeparator: { " \n,()[]`'\".;:/".contains($0) })
                where token.hasPrefix(prefix) {
                    named += 1
                    let tool = String(token.dropFirst(prefix.count))
                    XCTAssertTrue(
                        roster.contains(tool),
                        "(\(variant), \(phase)) names unknown pen tool '\(tool)'")
                }
            }
        }
        XCTAssertGreaterThan(named, 10, "the instruction prose names almost no pen tools")
    }

    /// Every agent def that names MCP tools must use the plugin-scoped prefix
    /// (a bare mcp__gmcc__ matcher never fires) and only registry names.
    func testAgentDefsUseScopedRosterNames() throws {
        let fm = FileManager.default
        let agentsDir = pluginRoot.appendingPathComponent("agents", isDirectory: true)
        guard fm.fileExists(atPath: agentsDir.path) else { return }
        let roster = VerbRegistry.penToolNames
        let enumerator = fm.enumerator(at: agentsDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                text.contains("mcp__gmcc__"),
                "\(url.lastPathComponent) uses the bare mcp__gmcc__ prefix — plugin tools are mcp__plugin_gmcc_pen__*")
            for match in text.split(whereSeparator: { " \n,()[]`'\"".contains($0) })
            where match.hasPrefix("mcp__plugin_gmcc_pen__") {
                let tool = String(match.dropFirst("mcp__plugin_gmcc_pen__".count))
                XCTAssertTrue(
                    roster.contains(tool),
                    "\(url.lastPathComponent) names unknown MCP tool '\(tool)'")
            }
        }
    }
}
