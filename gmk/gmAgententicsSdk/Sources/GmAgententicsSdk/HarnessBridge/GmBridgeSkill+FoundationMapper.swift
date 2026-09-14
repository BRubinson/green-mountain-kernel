import Foundation
import FoundationModels

@available(GmAgentOs 1.0, *)
extension GmConcept {

    public var toolFamilies: [GmAgentToolFamily] {
        switch self {
        case .gmcc: return [.dope, .diagram]
        case .personality: return []
        case .kbite: return [.kbite]
        case .cde: return [.cde, .rpir]
        case .project: return [.projects]
        case .kernel: return [.system, .fs]
        }
    }

    /// Every tool in this concept's families, MINUS the family placeholders.
    ///
    /// PUBLISHED AND GRANTED ARE DIFFERENT THINGS. The `*_not_supported` tools
    /// are deliberately SERVED — they appear in `tools/list` with a description
    /// naming why the family is unavailable, so an agent that goes looking finds
    /// an answer instead of a silence. But GRANTING one costs a slot in every
    /// skill's `allowed-tools` for a tool whose only behaviour is to throw, and
    /// `.diagram` contributes nothing else at all, so the `gmcc` skill was
    /// spending a grant to advertise a refusal.
    ///
    /// Keyed on the `_not_supported` suffix, which is the bridge's own naming
    /// convention for exactly these three (`diagram`, `fs`, `system`) — the
    /// families that are unavailable in full. It deliberately does NOT filter
    /// the `notSupported` tools that name a real capability, because those are
    /// individually meaningful and a caller should be able to reach the specific
    /// refusal.
    public var bridgeMcpTools: [GmBridgeMcpTool] {
        toolFamilies
            .flatMap(GmBridgeMcpTool.tools(in:))
            .filter { !$0.name.hasSuffix("_not_supported") }
    }

    public var bridgeSkill: GmBridgeSkill.File {
        GmBridgeSkill.File(self)
    }
}

@available(GmAgentOs 1.0, *)
extension GmBridgeSkill.File {

    public init(_ concept: GmConcept) {
        self.init(
            name: concept.code,
            description: concept.brief,
            userInvocable: false,
            allowedTools: concept.bridgeMcpTools.map(GmBridgeSkill.Tool.mcp),
            body: concept.text
        )
    }
}
