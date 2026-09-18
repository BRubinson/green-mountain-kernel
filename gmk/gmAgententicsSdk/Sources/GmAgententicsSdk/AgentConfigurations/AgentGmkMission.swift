// The top-level mission passed into the phases: one per skill, mapping each phase to its staffing, workflow template and base step set.

import Foundation
import GmDaemonSdk

enum AgentGmkMission: String, Sendable, Hashable, Codable, CaseIterable {

    case task = "gm_bot_task"
    case bot = "gm_bot"
    case rpi = "gm_bot_rpi"
    case team = "gm_bot_team"

    var phases: [GmCdeRpirWorkflowPhase] {
        switch self {
        case .task:
            return GmCdeRpirWorkflowPhase.allCases
        case .bot:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser,
                .architecture, .planGate, .implement, .review, .reviewFix, .done,
            ]
        case .rpi:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                .architecture, .planGate, .implement, .review, .reviewFix, .done,
            ]
        case .team:
            return [
                .briefing, .explore, .clarifyOpen, .clarifyUser, .carePackage,
                .archOptions, .architecture, .planGate, .implement, .review,
                .reviewFix, .done,
            ]
        }
    }

    var lenses: [AgentGmkPersonality] {
        switch self {
        case .task, .bot, .rpi: return [.compliant]
        case .team: return AgentGmkPersonality.lenses
        }
    }

    var writesRecord: Bool {
        self != .task
    }

    var wearsEveryDirective: Bool {
        switch self {
        case .task, .bot, .rpi: return true
        case .team: return false
        }
    }

    var text: String {
        switch self {
        case .task: return GM_AGENT_TASK_MISSION
        case .bot: return GM_AGENT_BOT_MISSION
        case .rpi: return GM_AGENT_RPI_MISSION
        case .team: return GM_AGENT_TEAM_MISSION
        }
    }

    func directive(for phase: GmCdeRpirWorkflowPhase) -> AgentGmkDirective {
        phase.directive
    }

    func baseSteps(for phase: GmCdeRpirWorkflowPhase) -> String {
        phase.directive.steps
    }

    func staffing(for phase: GmCdeRpirWorkflowPhase) -> String {
        guard writesRecord else { return GM_CDE_STAFF_IN_MIND }
        switch phase {
        case .clarifyUser, .planGate, .architecture, .done:
            return GM_CDE_STAFF_PRIMARCH
        case .briefing:
            return GM_CDE_STAFF_ONE_SINGLE_DIRECTIVE
        case .implement, .reviewFix:
            return self == .bot ? GM_CDE_STAFF_IN_CONTEXT : GM_CDE_STAFF_ONE_PER_SLICE
        case .explore, .archOptions, .review:
            switch self {
            case .bot: return GM_CDE_STAFF_IN_CONTEXT
            case .rpi: return GM_CDE_STAFF_ONE_MULTI_DIRECTIVE
            case .team: return GM_CDE_STAFF_ONE_PER_LENS
            case .task: return GM_CDE_STAFF_IN_MIND
            }
        case .clarifyOpen, .carePackage:
            switch self {
            case .bot: return GM_CDE_STAFF_IN_CONTEXT
            case .rpi: return GM_CDE_STAFF_ONE_MULTI_DIRECTIVE
            case .team: return GM_CDE_STAFF_ONE_SINGLE_DIRECTIVE
            case .task: return GM_CDE_STAFF_IN_MIND
            }
        }
    }

    func template(for phase: GmCdeRpirWorkflowPhase) -> String {
        """
        \(phase.template)

        \(staffing(for: phase))
        """
    }
}

extension GmCdeRpirWorkflowPhase {

    /// This layer's phase, as the DAEMON's phase.
    ///
    /// An exhaustive switch with NO `default:`, deliberately. With the contract
    /// test tier deleted, this is the only mechanism left that fails the build
    /// when the daemon grows a phase — a `rawValue` bridge would compile forever
    /// and return `nil` for a phase the daemon had already started serving.
    var specPhase: WorkflowSpec.Phase {
        switch self {
        case .briefing: return .briefing
        case .explore: return .explore
        case .clarifyOpen: return .clarifyOpen
        case .clarifyUser: return .clarifyUser
        case .carePackage: return .carePackage
        case .archOptions: return .archOptions
        case .architecture: return .architecture
        case .planGate: return .planGate
        case .implement: return .implement
        case .review: return .review
        case .reviewFix: return .reviewFix
        case .done: return .done
        }
    }

    /// The phase's instruction text.
    ///
    /// THESE CONSTANTS ARE THE NEWER DESCRIPTION, NOT A STALE COPY — read that
    /// before "consolidating" them into `WorkflowSpec`. They are structured
    /// (**Calls** / **Gate**), and they already spell the `cde` tool vocabulary,
    /// which `WorkflowSpec` only acquired by a mechanical rename. The direction
    /// of travel is `WorkflowSpec` → these, not the other way round.
    ///
    /// A v30 change briefly pointed this at `WorkflowSpec.instructions` on the
    /// theory that the constants were the duplicate. They are not; that reversed
    /// the arrow and fed the new layer the old text. Recorded because the mistake
    /// is an easy one to make twice — CLAUDE.md still asserts phase text is "read
    /// live from WorkflowSpec", which is the claim that invites it.
    ///
    /// TWO DESCRIPTIONS DO COEXIST TODAY, and the platform floor is why: this
    /// package is macOS 27 and `WorkflowSpec` lives in the macOS 14 base, so the
    /// daemon cannot read these constants at `BOT_NEXT` time. They are reconciled
    /// where BOTH are reachable — the plugin generator, which is macOS 27 and
    /// depends on the SDK.
    var template: String {
        switch self {
        case .briefing: return GM_CDE_PHASE_BRIEFING_TEMPLATE
        case .explore: return GM_CDE_PHASE_EXPLORE_TEMPLATE
        case .clarifyOpen: return GM_CDE_PHASE_CLARIFY_OPEN_TEMPLATE
        case .clarifyUser: return GM_CDE_PHASE_CLARIFY_USER_TEMPLATE
        case .carePackage: return GM_CDE_PHASE_CARE_PACKAGE_TEMPLATE
        case .archOptions: return GM_CDE_PHASE_ARCH_OPTIONS_TEMPLATE
        case .architecture: return GM_CDE_PHASE_ARCHITECTURE_TEMPLATE
        case .planGate: return GM_CDE_PHASE_PLAN_GATE_TEMPLATE
        case .implement: return GM_CDE_PHASE_IMPLEMENT_TEMPLATE
        case .review: return GM_CDE_PHASE_REVIEW_TEMPLATE
        case .reviewFix: return GM_CDE_PHASE_REVIEW_FIX_TEMPLATE
        case .done: return GM_CDE_PHASE_DONE_TEMPLATE
        }
    }
}
