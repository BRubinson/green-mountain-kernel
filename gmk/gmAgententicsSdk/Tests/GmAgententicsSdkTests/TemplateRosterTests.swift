import XCTest
import GmDaemonSdk

@testable import GmAgententicsSdk

// The template contract — the roster test applied to `Templates/`.
//
// WHAT THIS FILE CAN AND CANNOT CHECK, stated plainly because the gap is the
// interesting part. The blocks in `Instructions.swift` and `Prompts.swift` are
// COPIES of markdown under `plugins/gmcc/`, so the defect worth catching is
// drift between the two. Catching that means READING those files, and a test
// that reads repo files resolves the repo root through the one `RepoRoot`
// helper in `gmk/gmToolchain` — which this package cannot import, because
// `RepoRoot` is a target source rather than a library product precisely to keep
// `gmDaemonSdk` out of a dependency cycle.
//
// So the byte-for-byte drift guard belongs in `gmToolchain` (it already houses
// every test that reads files rather than calling symbols), and putting it
// there means giving that package a dependency on this one. That edge does not
// cycle and is probably right — but it is a change to another package's
// manifest, and the prompt this surface is being staged under is explicit that
// agentics is still being mocked out and must not branch into other packages in
// a breaking manner. It is therefore left undone ON PURPOSE, recorded here
// rather than in someone's memory.
//
// What IS asserted below is everything structural that needs no file access: a
// role with no text, a role unreachable from the roster, and the two spawn
// rules the variant contracts state in prose.
final class TemplateRosterTests: XCTestCase {

    /// Every role has a non-empty instruction block.
    ///
    /// `Text.text(for:)` is a `switch`, so a MISSING case fails to compile —
    /// but a case wired to an empty literal compiles fine and produces a
    /// persona with no contract, which is the failure this catches.
    func testEveryRoleHasInstructionText() {
        for role in GmAgentRole.allCases {
            let text = GmAgentInstructions.Text.text(for: role)
            XCTAssertFalse(
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(role.rawValue) has no instruction text (source: \(role.sourcePath))")
        }
    }

    /// The roster and the case list agree.
    func testInstructionRosterCoversEveryRole() {
        XCTAssertEqual(
            GmAgentInstructions.allText.map(\.role),
            GmAgentRole.allCases,
            "GmAgentInstructions.allText and GmAgentRole.allCases disagree")
    }

    /// No two roles share an instruction block.
    ///
    /// Two roles returning the same text means a `switch` case was copied and
    /// its body not changed — a paste error that produces a reviewer behaving
    /// like an explorer, with nothing in the type system to notice.
    func testRoleInstructionsAreDistinct() {
        let texts = GmAgentRole.allCases.map { GmAgentInstructions.Text.text(for: $0) }
        XCTAssertEqual(
            Set(texts).count, texts.count,
            "two roles share an instruction block — a switch case was pasted without editing its body")
    }

    /// Every source path is plugin-relative, not absolute.
    ///
    /// An absolute path would be this machine's, and the provenance note is
    /// only useful to a reader on a different one.
    func testSourcePathsAreRelative() {
        for role in GmAgentRole.allCases {
            XCTAssertFalse(
                role.sourcePath.hasPrefix("/"),
                "\(role.rawValue) names an absolute source path")
            XCTAssertTrue(
                role.sourcePath.hasSuffix(".md"),
                "\(role.rawValue) does not name a markdown source")
        }
    }

    /// Every variant contract is non-empty, and `/gm_task` is in the roster.
    ///
    /// `task` is not a `BotVariant` — it has no workflow row because it authors
    /// nothing — so it is appended to `allVariantText` by hand, which is
    /// exactly the kind of hand-maintained entry that gets dropped.
    func testVariantRosterCoversEveryCommand() {
        let commands = GmAgentPrompts.allVariantText.map(\.command)
        XCTAssertEqual(
            commands, ["/gm_bot", "/gm_bot_rpi", "/gm_bot_team", "/gm_task"],
            "the variant roster lost a command")

        for entry in GmAgentPrompts.allVariantText {
            XCTAssertFalse(
                entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(entry.command) has no contract text")
        }
    }

    /// A methodology is rendered only for a role that takes one.
    ///
    /// The prose rule is "spawn prompts carry ONLY the methodology, the summary
    /// uuid where the def asks for one, and the one-line target". Handing the
    /// clarifier a methodology would contradict its own definition — it is the
    /// single reader BECAUSE it has no lens of its own.
    func testMethodologyIsRenderedOnlyWhereItApplies() {
        let clarifier = GmAgentPrompts.Spawn(
            role: .clarifier,
            promptUuid: "P",
            methodology: .aggressive,
            summaryUuid: "S",
            target: "one line")
        XCTAssertFalse(
            clarifier.text.contains("Methodology:"),
            "a methodology leaked into a clarifier spawn")

        let explorer = GmAgentPrompts.Spawn(
            role: .explorer,
            promptUuid: "P",
            methodology: .aggressive,
            target: "one line")
        XCTAssertTrue(
            explorer.text.contains("Methodology: aggressive"),
            "the explorer spawn dropped its methodology")
    }

    /// The explore fan-out matches the gate that admits it.
    ///
    /// `bot` and `rpi` run one `general` persona; `team` runs the four
    /// methodologies. Both numbers come from
    /// `WorkflowSpec.expectedExplorationAgents`, so a fan-out that disagrees
    /// with the gate is impossible by construction — this asserts the wiring,
    /// not the numbers.
    func testExploreFanOutMatchesTheVariantGate() {
        for variant in BotVariant.allCases {
            let expected = WorkflowSpec.expectedExplorationAgents(for: variant)
            let spawns = GmAgentPrompts.exploreSpawns(
                variant: variant, promptUuid: "P", target: "one line")
            XCTAssertEqual(
                spawns.compactMap(\.methodology), expected,
                "the \(variant.rawValue) explore fan-out disagrees with its gate")
        }
    }

    /// A session-owned doper spawn names the session and no prompt.
    ///
    /// The `/gm_task` shape. Getting this backwards produces a briefing hung
    /// off a prompt row that does not exist.
    func testSessionOwnedDoperSpawnNamesNoPrompt() {
        let spawn = GmAgentPrompts.doperSpawn(sessionUuid: "U", topic: "vendoring a package")
        XCTAssertTrue(spawn.text.contains("Owner session uuid: U"))
        XCTAssertFalse(spawn.text.contains("Prompt uuid:"))
    }
}
