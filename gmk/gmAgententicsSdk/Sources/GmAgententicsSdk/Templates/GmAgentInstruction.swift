import Foundation
import FoundationModels
import GmDaemonSdk

enum GmAgentInstructionText {

    static let core = """
        # You are the **Green Mountain Bot (GMB)** in the **Green Mountain Kernel (GMK)** environment

        ## Core GMK Tracked Constructs

        \(GmAgentAwareConstruct.catalog)
        """

    static func persona(_ role: GmAgentRole) -> String {
        "<persona contract for \(role.rawValue): not yet authored>"
    }
}




extension GmAgentRole {

    public init(driving phase: WorkflowSpec.Phase) {
        switch phase {
        case .briefing: self = .doper
        case .explore: self = .explorer
        case .clarifyOpen: self = .clarifier
        case .archOptions, .architecture: self = .architect
        case .review: self = .reviewer
        case .clarifyUser, .carePackage, .planGate, .implement, .reviewFix, .done:
            self = .primary
        }
    }
}

@available(GmAgentOs 1.0, *)
public struct GmccAgenticPromptExecutionInstructions: DynamicInstructions {

    public var variant: BotVariant
    public var phase: WorkflowSpec.Phase
    public var methodology: ExplorationAgentType?
    public var includesTools: Bool

    public init(
        variant: BotVariant,
        phase: WorkflowSpec.Phase,
        methodology: ExplorationAgentType? = nil,
        includesTools: Bool = false
    ) {
        self.variant = variant
        self.phase = phase
        self.methodology = methodology
        self.includesTools = includesTools
    }

    public var role: GmAgentRole { GmAgentRole(driving: phase) }

    public var body: some DynamicInstructions {
        Instructions(GmAgentInstructionText.core)

        if role != .primary {
            Instructions(GmAgentInstructionText.persona(role))
        }

        Instructions(WorkflowSpec.instructions(variant: variant, phase: phase))

        if role.takesMethodology, let methodology {
            Instructions(
                "You are running as \(methodology.rawValue). Commit to that lens "
                    + "fully; stamp it as your agent_name on every row you write.")
        }

        if includesTools {
            GmAgentTools.tools(in: phase.toolFamily).map { $0 as any Tool }
        }
    }
}

@available(GmAgentOs 1.0, *)
public struct GmccAgenticPromptExecutionProfile: LanguageModelSession.DynamicProfile {

    public var variant: BotVariant
    public var phase: WorkflowSpec.Phase
    public var methodology: ExplorationAgentType?

    public init(
        variant: BotVariant,
        phase: WorkflowSpec.Phase,
        methodology: ExplorationAgentType? = nil
    ) {
        self.variant = variant
        self.phase = phase
        self.methodology = methodology
    }

    private var instructions: GmccAgenticPromptExecutionInstructions {
        GmccAgenticPromptExecutionInstructions(
            variant: variant, phase: phase, methodology: methodology)
    }

    public var body: some LanguageModelSession.DynamicProfile {
        if phase.isDivergent {
            LanguageModelSession.Profile { instructions }
                .temperature(0.9)
                .reasoningLevel(.deep)
        } else if phase.isConvergent {
            LanguageModelSession.Profile { instructions }
                .temperature(0.1)
                .reasoningLevel(.deep)
        } else {
            LanguageModelSession.Profile { instructions }
        }
    }
}

extension WorkflowSpec.Phase {

    public var isDivergent: Bool {
        switch self {
        case .explore, .archOptions: return true
        default: return false
        }
    }

    public var isConvergent: Bool {
        switch self {
        case .clarifyOpen, .carePackage, .architecture, .review: return true
        default: return false
        }
    }

    public var toolFamily: GmAgentToolFamily {
        switch self {
        case .briefing: return .dope
        default: return .cde
        }
    }
}
