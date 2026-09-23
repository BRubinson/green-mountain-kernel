import Foundation
import FoundationModels

extension GmConcept {

    var toolFamilies: [GmAgentToolFamily] {
        switch self {
        // `gmcc` grants nothing of its own now that dope has its own concept:
        // `.diagram` is a refusal-only family (see `bridgeMcpTools`), and the
        // dope tools belong to the skill that carries the dope rules.
        case .gmcc: return [.diagram]
        case .dope: return [.dope]
        case .personality: return []
        case .kbite: return [.kbite]
        case .cde: return [.cde, .rpir]
        case .project: return [.projects]
        case .kernel: return [.system, .fs]
        }
    }

    /// Every tool in this concept's families, MINUS the family placeholders.
    ///
    /// Published and granted are different things. The `*_not_supported` tools are
    /// served so an agent that goes looking finds an answer, but granting one costs
    /// a slot in every skill's `allowed-tools` for a tool whose only behaviour is
    /// to throw. Keyed on the suffix, which names the three families unavailable in
    /// full, so a `notSupported` tool naming a real capability stays grantable and
    /// its specific refusal stays reachable.
    var bridgeMcpTools: [GmBridgeMcpTool] {
        toolFamilies
            .flatMap(GmBridgeMcpTool.tools(in:))
            .filter { !$0.name.hasSuffix("_not_supported") }
    }

    var bridgeSkill: GmBridgeSkill.File {
        GmBridgeSkill.File(self)
    }
}

extension GmBridgeSkill.File {

    /// Creates a bridge skill file from a concept.
    /// - Parameter concept: The concept to derive the skill from.
    init(_ concept: GmConcept) {
        self.init(
            name: concept.code,
            description: concept.brief,
            userInvocable: false,
            allowedTools: concept.bridgeMcpTools.map(GmBridgeSkill.Tool.mcp),
            body: concept.text
        )
    }
}
