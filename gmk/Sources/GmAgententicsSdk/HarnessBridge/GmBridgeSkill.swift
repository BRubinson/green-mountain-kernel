import Foundation

extension GmBridgeSkill {

    public static let all: [File] = GmConcept.allCases.map(File.init)

    public static func file(for concept: GmConcept) -> File {
        File(concept)
    }
}
