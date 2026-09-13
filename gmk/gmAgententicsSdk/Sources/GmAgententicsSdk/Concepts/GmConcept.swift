import Foundation

public enum GmConcept: String, Sendable, Hashable, Codable, CaseIterable {

    case gmcc

    case personality

    case kbite

    case cde

    case project

    case kernel

    public var code: String { rawValue }

    public var brief: String {
        switch self {
        case .gmcc: return "The coding collection to support gmk"
        case .personality: return "The methodology lenses a fan-out agent wears"
        case .kbite: return "Pre-indexed external knowledge"
        case .cde: return "The harness integration for agentic development"
        case .project: return "Identity spine: project, instance, session"
        case .kernel: return "One binary, sole writer, one filesystem root"
        }
    }

    public var text: String {
        switch self {
        case .gmcc: return GM_CONCEPT_GMCC
        case .personality: return GM_CONCEPT_PERSONALITY
        case .kbite: return GM_CONCEPT_KBITE
        case .cde: return GM_CONCEPT_CDE
        case .project: return GM_CONCEPT_PROJECT
        case .kernel: return GM_CONCEPT_KERNEL
        }
    }
}
