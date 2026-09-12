import Testing
import GMCCDaemonKit
@testable import GMVibes

/// The first real tests in this target.
///
/// `WorkflowStripModel` is the one piece of the workflow UI worth unit
/// testing, and it is testable precisely because it has no SwiftUI import.
/// Each test below is one degraded state a daemon/app version skew actually
/// produces — the states that would otherwise live as prose in a view body
/// and be verified by squinting at a running app.
struct WorkflowStripModelTests {

    // MARK: - Fixtures

    private static func workflow(
        variant: String,
        status: String = "active",
        lastServedPhase: String? = nil
    ) -> BotWorkflowRow {
        BotWorkflowRow(
            uuid: "wf-1",
            version: 1,
            sessionUuid: "sess-1",
            promptUuid: "prompt-1",
            variant: variant,
            status: status,
            clientKey: nil,
            lastServedPhase: lastServedPhase,
            reconcileGitHead: nil,
            createdAt: "2026-09-11T00:00:00Z",
            updatedAt: "2026-09-11T00:00:00Z")
    }

    private static func response(
        variant: String,
        phase: String,
        status: String = "active",
        blockers: [String] = []
    ) -> BotNextResponse {
        BotNextResponse(
            workflow: workflow(variant: variant, status: status, lastServedPhase: phase),
            phase: phase,
            instructions: "instructions for \(phase)",
            gateBlockers: blockers,
            uuids: BotPhaseUuids(
                promptUuid: "prompt-1",
                sessionUuid: "sess-1",
                briefingUuid: nil,
                clarificationSummaryUuid: nil,
                carePackageUuid: nil,
                architectureSummaryUuid: nil,
                reviewSummaryUuid: nil,
                explorationSummaryUuids: [:]))
    }

    // MARK: - The three variants walk their own graph

    @Test func variantGraphsAndCurrentIndex() {
        let expected: [(BotVariant, Int)] = [(.bot, 10), (.rpi, 11), (.team, 12)]
        for (variant, count) in expected {
            let model = WorkflowStripModel.make(
                Self.response(variant: variant.rawValue, phase: "implement"))

            #expect(model.pills.count == count)
            #expect(model.variantLabel == "\(variant.rawValue) · \(count) phases")
            #expect(model.closed == false)

            let graph = WorkflowSpec.phases(for: variant)
            let servedIndex = graph.firstIndex(of: .implement)!

            #expect(model.pills.map(\.id) == graph.map(\.rawValue))
            #expect(model.pills.filter { $0.state == .current }.map(\.id) == ["implement"])
            #expect(model.pills[..<servedIndex].allSatisfy { $0.state == .done })
            #expect(model.pills[(servedIndex + 1)...].allSatisfy { $0.state == .pending })
            // Instructions are the compiled-in prose verbatim, per pill.
            #expect(model.pills[servedIndex].instructions
                == WorkflowSpec.instructions(variant: variant, phase: .implement))
        }
    }

    @Test func phaseTitlesAreHumanised() {
        let model = WorkflowStripModel.make(
            Self.response(variant: "rpi", phase: "clarify_user"))
        #expect(model.pills.first(where: { $0.id == "clarify_user" })?.title == "Clarify User")
        #expect(model.pills.first(where: { $0.id == "care_package" })?.title == "Care Package")
    }

    // MARK: - Rule 1: unrecognised variant

    @Test func unrecognisedVariantDegradesToOnePill() {
        let model = WorkflowStripModel.make(
            Self.response(variant: "swarm", phase: "implement",
                          blockers: ["review not complete"]))

        #expect(model.variantLabel == nil)          // the degraded marker
        #expect(model.pills.count == 1)             // never an empty graph
        #expect(model.pills[0].id == "implement")   // the SERVED phase string
        #expect(model.pills[0].title == "Implement")
        #expect(model.pills[0].state == .current)   // the highlight survives
        #expect(model.pills[0].instructions == nil) // no (variant, phase) pair
        #expect(model.blockers == ["review not complete"])
    }

    @Test func unrecognisedVariantOnAClosedRunIsDone() {
        let model = WorkflowStripModel.make(
            Self.response(variant: "swarm", phase: "done", status: "done"))
        #expect(model.variantLabel == nil)
        #expect(model.pills.map(\.state) == [.done])
        #expect(model.closed)
    }

    // MARK: - Rule 2: unknown served phase

    @Test func unknownServedPhaseAppendsATrailingPill() {
        let model = WorkflowStripModel.make(
            Self.response(variant: "rpi", phase: "warp_drive"))

        let graph = WorkflowSpec.phases(for: .rpi)
        #expect(model.pills.count == graph.count + 1)
        #expect(model.pills.map(\.id).dropLast() == ArraySlice(graph.map(\.rawValue)))

        let trailing = model.pills.last!
        #expect(trailing.id == "warp_drive")
        #expect(trailing.title == "Warp Drive")
        #expect(trailing.state == .unknown)         // highlight PRESERVED, not dropped
        #expect(trailing.instructions == nil)

        // Nothing in the graph is known to be behind an unknown phase, so
        // nothing claims .done and nothing claims .current.
        #expect(model.pills.dropLast().allSatisfy { $0.state == .pending })
        #expect(!model.pills.contains { $0.state == .current })
        #expect(model.variantLabel == "rpi · \(graph.count) phases")
    }

    @Test func knownPhaseMissingFromThisVariantsGraphIsAlsoUnknown() {
        // care_package is a real WorkflowSpec.Phase, but `bot` never walks it.
        let model = WorkflowStripModel.make(
            Self.response(variant: "bot", phase: "care_package"))
        #expect(model.pills.last?.id == "care_package")
        #expect(model.pills.last?.state == .unknown)
        #expect(model.pills.count == WorkflowSpec.phases(for: .bot).count + 1)
    }

    // MARK: - Rule 3: closed workflow

    @Test func closedWorkflowIsAllDoneWithNoCurrent() {
        // Reachable: BotWorkflowRepository.resolve falls back to the most
        // recent CLOSED row for read verbs, so every done prompt lands here.
        let model = WorkflowStripModel.make(
            Self.response(variant: "team", phase: "done", status: "done"))

        #expect(model.closed)
        #expect(model.pills.count == WorkflowSpec.phases(for: .team).count)
        #expect(model.pills.allSatisfy { $0.state == .done })
        #expect(!model.pills.contains { $0.state == .current })
    }

    @Test func closedWorkflowParkedMidGraphStillReadsAsFinished() {
        // A run closed while the derived phase was still `implement` must
        // read as finished, not as a run parked mid-graph.
        let model = WorkflowStripModel.make(
            Self.response(variant: "rpi", phase: "implement", status: "done"))
        #expect(model.closed)
        #expect(model.pills.allSatisfy { $0.state == .done })
    }

    @Test func closedWorkflowWithAnUnknownPhaseKeepsItVisibleAsDone() {
        // Rule 3 overrides rule 2's `.unknown`: closed wins everywhere. The
        // skewed phase stays VISIBLE rather than being dropped.
        let model = WorkflowStripModel.make(
            Self.response(variant: "rpi", phase: "warp_drive", status: "done"))
        #expect(model.pills.last?.id == "warp_drive")
        #expect(model.pills.allSatisfy { $0.state == .done })
    }

    // MARK: - Blockers pass through untouched

    @Test func blockersAreServedProse() {
        let blockers = ["synthesis summary (the prompt-level seal) incomplete",
                        "clarification suite not sealed (status: building)"]
        let model = WorkflowStripModel.make(
            Self.response(variant: "bot", phase: "explore", blockers: blockers))
        #expect(model.blockers == blockers)
    }
}
