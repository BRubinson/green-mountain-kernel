import Foundation

extension GmBridgeSkill {

    static let all: [File] = GmConcept.allCases.map(File.init)

    /// Returns the skill file for the given GmConcept.
    /// - Parameter concept: The concept.
    /// - Returns: The corresponding skill file.
    static func file(for concept: GmConcept) -> File {
        File(concept)
    }
}
