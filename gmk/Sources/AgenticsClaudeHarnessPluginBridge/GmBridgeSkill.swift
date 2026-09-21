import Foundation

extension GmBridgeSkill {

    static let all: [File] = GmConcept.allCases.map(File.init)

    static func file(for concept: GmConcept) -> File {
        File(concept)
    }
}
