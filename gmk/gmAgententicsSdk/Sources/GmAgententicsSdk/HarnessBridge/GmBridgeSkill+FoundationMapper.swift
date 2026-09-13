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

    public var bridgeMcpTools: [GmBridgeMcpTool] {
        toolFamilies.flatMap(GmBridgeMcpTool.tools(in:))
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
