// The workflow phases and the directive that owns each one.

import Foundation

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
}
