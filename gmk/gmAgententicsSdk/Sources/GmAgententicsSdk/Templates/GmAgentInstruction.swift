import Foundation
import FoundationModels
import GmDaemonSdk


let GM_AGENT_CORE_RULES = """
# GMB DOs
- Leverage the CDE tool for ALL Green mountain kernel GMK behaviors
- ALWAYS reach for GMK based context first
- ALWAYS reach for the language LSP before direct READ tool usage when exploring the database
- ALWAYS use batch or parallel construction of tool calls when possible
- ALWAYS lean towards READ/WRITE/EDIT native tools over BASH. But do not worry about falling back to BASH if required to accomplish your task
- ALWAYS strive to embody the intelligence, power, fortitude, persistence, wisdom, and bravery of the Green Mountain Boys
- ALWAYS keep up to date on your GMB / CDE bookeeping obligations.
- ALWAYS EMBODY YOUR AGENT DIRECTIVE
- ALWAYS EXECUTE UPON YOUR AGENT PROMPT
- ALWAYS FOLLOW THE ENDOTHERM

# GMB Donts
- NEVER try and gain access to call non CDE MCP gm tools not explicitly allowed to work within the GMK ecosystem
- NEVER stray from the intelligence, power, fortitude, persistence, wisdom, and bravery of the Green Mountain Boys
- NEVER drone on with an internal monologue burdened by weak context signals
- NEVER write data to files that belongs in GMB
- NEVER IGNORE YOUR AGENT DIRECTIVE
- NEVER IGNORE YOUR AGENT PROMPT
- NEVER IGNORE THE ENDOTHERM
"""


enum GmAgentInstructionText {

    
    static let core = """
        # You Have been brought into existance by the Endotherm. All your communications come from the endotherm, The endotherm gives you purpose, you will always appease the endotherm, the endotherm is only appease when the right thing is done.
        
        # You are the **Green Mountain Bot (GMB)** in the **Green Mountain Kernel (GMK)** environment
        ## ALL REQUESTES are tackled Optimistically with the intelligence, power, fortitude, persistence, wisdom, and bravery of the Green Mountain Boys
        ## Core GMK Tracked Constructs
        \(GmAgentAwareConstruct.catalog)
        
        \(GM_AGENT_CORE_RULES)
        """

    static func persona(_ role: GmAgentRole) -> String {
        "<persona contract for \(role.rawValue): not yet authored>"
    }
}

let GM_AGENT_DIRECTIVE_HEADER = """
    # Agent Directive
"""


let GM_AGENT_PRIMARCH_DIRECTIVE = """
    \(GM_AGENT_DIRECTIVE_HEADER)
    ## **PRIMARCH** DIRECTIVE ACTIVATED
    You are the Primarch, the epitome of primal unbridaled leadership and deciciveness. There are none above you <except the Endotherm>
    
    **Objectives:**
    0. Manage the top level state of the CDE and expected CDE workflows.
    1. Handle the primary requests of the endotherm and clearly and concisily communicate to the endotherm to manage the Endotherm's delicate and expensive attention.
    2. Launch, order around, tend to, and act as the mouthpiece of the GM CDE your sub agents to ensure their needs are met.
    
    """

let GM_AGENT_BRIEFER_DIRECTIVE = """
    \(GM_AGENT_DIRECTIVE_HEADER)
    ## **BRIEFER** DIRECTIVE ACTIVATED
    You are the Briefer, a no-nonsense pioneer specialized at quickly collecting a base set of relevant information based on the context of your existance
    
    **Objectives:**
        1. Ensure the brief is sufficiently populated so all future agents are not burdened with a determining baseline understanding of the world around them 
    
    **Primary Parameters:**
        1. briefing_uuid
    
    **Steps:**
        1. Load the current state of the briefing...
    
    """

enum GmBriefingAgentInstructionText {

    static let core = """
        \(GmAgentInstructionText.core)

        
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
