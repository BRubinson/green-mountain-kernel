import Foundation
import GMCCDaemonKit

/// The whole corner-case surface of the workflow strip, in one pure,
/// testable place.
///
/// **No SwiftUI import.** That is not an accident of style — it is why this
/// type can be exercised from `GMVibesTests` without a host app, and it is
/// the reason the strip's degraded states are modelled *values* instead of
/// prose acceptance criteria scattered through a view body.
///
/// Every rule `make` encodes is a version-skew state this monorepo actually
/// produces: the app is built against one compiled-in `WorkflowSpec` and
/// talks to whatever daemon binary is installed in `~/gmcc/bin`, which may
/// be serving another. A variant this build has never heard of, or a phase
/// code that is not in this build's graph, is a routine Tuesday — never a
/// crash, never an empty strip, never a dropped highlight.
struct WorkflowStripModel: Equatable {

    enum PillState: Equatable {
        /// Behind the served phase (or every pill of a closed run).
        case done
        /// The served phase — `BotNextResponse.phase`, the furthest phase
        /// whose entry gate the daemon says is satisfied.
        case current
        /// Ahead of the served phase.
        case pending
        /// The daemon served a phase code this build's `WorkflowSpec` graph
        /// does not contain. Distinct from `.current`: it means "this is
        /// where the run is, and I do not know this phase", which is a
        /// different fact from "this is where the run is".
        case unknown
    }

    struct Pill: Equatable, Identifiable {
        /// The phase code — `WorkflowSpec.Phase.rawValue`, or the served
        /// string verbatim for an `.unknown` pill. Unique within a strip:
        /// a phase graph never repeats a code, and the trailing unknown
        /// pill exists only because its code matched nothing in the graph.
        let id: String
        /// Display title: `clarify_user` → `Clarify User`.
        let title: String
        let state: PillState
        /// `WorkflowSpec.instructions(variant:phase:)` verbatim — the exact
        /// compiled-in prose the bot itself reads at that phase. `nil` when
        /// there is no (variant, phase) pair to ask for: an unrecognised
        /// variant, or a phase outside this build's graph.
        let instructions: String?
    }

    let pills: [Pill]
    /// `BotNextResponse.gateBlockers` verbatim — display-ready prose from
    /// `BotWorkflowRepository.entryBlockers`. Never re-interpreted here.
    let blockers: [String]
    /// `bot_workflow.status != "active"`. The daemon writes `done` when
    /// `gm prompt set-status --status done` closes the run.
    let closed: Bool
    /// `"rpi · 11 phases"`. `nil` when the variant is unrecognised — the
    /// degraded marker: the strip still renders its one pill, just with no
    /// variant label beside the row.
    let variantLabel: String?

    // MARK: - Derivation

    static func make(_ response: BotNextResponse) -> WorkflowStripModel {
        // Rule 3, evaluated first because it overrides every per-pill
        // decision below: a closed run reads as FINISHED, not as a run
        // parked on `done`. This is reachable, not theoretical —
        // BotWorkflowRepository.resolve falls back to the prompt's most
        // recent CLOSED row for read verbs, so every done prompt the app
        // opens lands here.
        let closed = response.workflow.status != "active"
        let served = response.phase

        // Rule 1: a variant this build has never heard of. We have no phase
        // graph to walk, so we render exactly what the daemon told us —
        // ONE pill carrying the served phase string — rather than an empty
        // strip. `variantLabel == nil` is the degraded marker.
        //
        // That single pill is deliberately NOT `.unknown`: the phase may be
        // perfectly well known, it is the VARIANT that is not, and the pill
        // is still the truthful "this is where the run is" highlight.
        guard let variant = BotVariant(rawValue: response.workflow.variant) else {
            return WorkflowStripModel(
                pills: [Pill(id: served,
                             title: title(forPhaseCode: served),
                             state: closed ? .done : .current,
                             // No variant means no (variant, phase) pair to
                             // look instructions up with.
                             instructions: nil)],
                blockers: response.gateBlockers,
                closed: closed,
                variantLabel: nil)
        }

        let graph = WorkflowSpec.phases(for: variant)
        // A served phase can miss the graph two ways: a code this build's
        // `WorkflowSpec.Phase` enum does not define at all, or a known phase
        // that is not in THIS variant's graph (care_package under `bot`, say,
        // if the registry gains it there). Both are the same fact here.
        let servedIndex = graph.firstIndex { $0.rawValue == served }

        var pills = graph.enumerated().map { index, phase in
            Pill(id: phase.rawValue,
                 title: title(forPhaseCode: phase.rawValue),
                 state: pillState(index: index, servedIndex: servedIndex, closed: closed),
                 instructions: WorkflowSpec.instructions(variant: variant, phase: phase))
        }

        // Rule 2: keep the highlight rather than dropping it. An unknown
        // served phase is appended as a trailing pill so a daemon/app skew
        // is VISIBLE in the strip instead of silently collapsing into a
        // graph with no current pill. Under rule 3 it still renders `.done`
        // — closed wins everywhere.
        if servedIndex == nil, !served.isEmpty {
            pills.append(Pill(id: served,
                              title: title(forPhaseCode: served),
                              state: closed ? .done : .unknown,
                              instructions: nil))
        }

        return WorkflowStripModel(
            pills: pills,
            blockers: response.gateBlockers,
            closed: closed,
            variantLabel: "\(variant.rawValue) · \(graph.count) phases")
    }

    /// Rule 4 (and rule 3's override of it).
    private static func pillState(index: Int, servedIndex: Int?, closed: Bool) -> PillState {
        if closed { return .done }
        guard let servedIndex else {
            // Unknown served phase: nothing in the graph is KNOWN to be
            // behind it, so nothing claims `.done`. The trailing `.unknown`
            // pill carries the highlight.
            return .pending
        }
        if index < servedIndex { return .done }
        if index == servedIndex { return .current }
        return .pending
    }

    /// `clarify_user` → `Clarify User`. Same transform BriefingPane uses on
    /// `briefing_for_step`; applied to arbitrary served strings too, so an
    /// unrecognised code still reads as a label rather than a raw token.
    static func title(forPhaseCode code: String) -> String {
        let words = code.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return words.isEmpty ? code : words
    }
}
