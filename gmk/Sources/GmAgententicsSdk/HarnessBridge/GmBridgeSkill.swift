import Foundation

@available(GmAgentOs 1.0, *)
extension GmBridgeSkill {

    public static let all: [File] = GmConcept.allCases.map(File.init)

    public static func file(for concept: GmConcept) -> File {
        File(concept)
    }
}
