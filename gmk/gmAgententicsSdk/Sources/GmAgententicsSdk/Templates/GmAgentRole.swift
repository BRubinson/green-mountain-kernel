import Foundation

public enum GmAgentRole: String, Sendable, Hashable, Codable, CaseIterable {

    case primary

    case doper

    case explorer

    case clarifier

    case architect

    case reviewer

    case kbiteChewer = "kbite_chewer"

    case mawFetcher = "maw_fetcher"

    public var takesMethodology: Bool {
        switch self {
        case .explorer, .architect, .reviewer: return true
        case .primary, .doper, .clarifier, .kbiteChewer, .mawFetcher: return false
        }
    }
}
