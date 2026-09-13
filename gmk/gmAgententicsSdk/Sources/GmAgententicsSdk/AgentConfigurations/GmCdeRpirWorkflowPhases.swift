// The RPIR workflow phases and the directive, instruction and wire phase each one maps to.

import Foundation
import GmDaemonSdk

enum GmCdeRpirWorkflowPhase: String, CaseIterable, Sendable {

    case briefing
    case explore
    case clarifyOpen = "clarify_open"
    case clarifyUser = "clarify_user"
    case carePackage = "care_package"
    case archOptions = "arch_options"
    case architecture
    case planGate = "plan_gate"
    case implement
    case review
    case reviewFix = "review_fix"
    case done

    init(_ phase: WorkflowSpec.Phase) {
        switch phase {
        case .briefing: self = .briefing
        case .explore: self = .explore
        case .clarifyOpen: self = .clarifyOpen
        case .clarifyUser: self = .clarifyUser
        case .carePackage: self = .carePackage
        case .archOptions: self = .archOptions
        case .architecture: self = .architecture
        case .planGate: self = .planGate
        case .implement: self = .implement
        case .review: self = .review
        case .reviewFix: self = .reviewFix
        case .done: self = .done
        }
    }

    var workflowPhase: WorkflowSpec.Phase {
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

    var directive: AgentGmkDirective {
        switch self {
        case .briefing: return .briefer
        case .explore: return .explorer
        case .clarifyOpen: return .intentClarifier
        case .architecture: return .architect
        case .archOptions: return .architect
        case .implement: return .implementor
        case .review: return .reviewer

        case .clarifyUser: return .primarch
        case .carePackage: return .intentClarifier
        case .planGate: return .primarch
        case .reviewFix: return .implementor
        case .done: return .primarch
        }
    }

    var instruction: GmAgentInstruction {
        switch self {
        case .briefing: return .briefer
        case .explore: return .explorer
        case .clarifyOpen: return .intentClarifier
        case .clarifyUser: return .primarch
        case .carePackage: return .intentClarifier
        case .archOptions: return .architect
        case .architecture: return .architect
        case .planGate: return .primarch
        case .implement: return .implementor
        case .review: return .reviewer
        case .reviewFix: return .implementor
        case .done: return .primarch
        }
    }

    var toolFamilies: [GmAgentToolFamily] {
        switch self {
        case .briefing:
            return [.cde, .dope, .kbite, .projects]
        case .explore:
            return [.cde, .dope, .kbite, .projects]
        case .clarifyOpen, .clarifyUser, .carePackage:
            return [.cde, .dope, .kbite]
        case .archOptions, .architecture:
            return [.cde, .dope, .kbite]
        case .planGate:
            return [.cde]
        case .implement:
            return [.cde, .dope, .fs]
        case .review, .reviewFix:
            return [.cde, .dope]
        case .done:
            return [.cde]
        }
    }

    static func phases(for variant: BotVariant) -> [GmCdeRpirWorkflowPhase] {
        WorkflowSpec.phases(for: variant).map(GmCdeRpirWorkflowPhase.init)
    }
}
