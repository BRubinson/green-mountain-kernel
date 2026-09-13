// Assembles a phase-keyed DynamicInstructions body and the session profile built over it.

import Foundation
import FoundationModels
import ClaudeForFoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
struct AgentPhaseInstructions: DynamicInstructions {

    let phase: GmCdeRpirWorkflowPhase

    let variant: BotVariant

    let personality: GmAgentPersonality

    var wearsEveryDirective: Bool {
        switch variant {
        case .bot, .rpi: return true
        case .team: return false
        }
    }

    init(
        phase: GmCdeRpirWorkflowPhase,
        variant: BotVariant,
        personality: GmAgentPersonality = .compliant
    ) {
        self.phase = phase
        self.variant = variant
        self.personality = personality
    }

    @DynamicInstructionsBuilder
    var body: some DynamicInstructions {
        Instructions(GM_AGENT_CORE)
        Instructions(personality.text)
        Instructions(directiveText)
        Instructions(WorkflowSpec.instructions(variant: variant, phase: phase.workflowPhase))
        Instructions(phase.instruction.text)
    }

    private var directiveText: String {
        guard wearsEveryDirective else { return phase.instruction.directive.text }
        return AgentGmkDirective.allCases.map(\.text).joined(separator: "\n\n")
    }
}

@available(GmAgentOs 1.0, *)
enum AgentSessionProfile {

    static func profile(
        for phase: GmCdeRpirWorkflowPhase,
        variant: BotVariant,
        personality: GmAgentPersonality = .compliant,
        auth: AuthMode = GM_AGENT_PLACEHOLDER_AUTH
    ) -> some LanguageModelSession.DynamicProfile {
        let directive = phase.directive
        return LanguageModelSession.Profile {
            AgentPhaseInstructions(
                phase: phase,
                variant: variant,
                personality: personality)
            phase.toolFamilies.flatMap { GmAgentTools.tools(in: $0) }
        }
        .model(directive.languageModel(auth: auth))
        .temperature(directive.temperature)
    }
}
