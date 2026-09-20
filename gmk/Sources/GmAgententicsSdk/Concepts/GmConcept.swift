import Foundation

/// The tracked concepts, each of which ships as ONE skill.
///
/// DECLARATION ORDER IS PRESENTATION ORDER: `GM_AGENT_CONSTRUCTS` renders
/// `allCases` in this sequence into every agent body and the output style, so
/// the list reads spine → work → self-model → knowledge → runtime → lenses →
/// umbrella. Reorder here, nowhere else.
public enum GmConcept: String, Sendable, Hashable, Codable, CaseIterable {

    case project

    case cde

    case dope

    case kbite

    case kernel

    case personality

    case gmcc

    public var code: String { rawValue }

    public var brief: String {
        switch self {
        case .gmcc: return "The coding collection to support gmk"
        case .dope: return "Domain Optimized Project Essence: the project's model of itself"
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
        case .dope: return GM_CONCEPT_DOPE
        case .personality: return GM_CONCEPT_PERSONALITY
        case .kbite: return GM_CONCEPT_KBITE
        case .cde: return GM_CONCEPT_CDE
        case .project: return GM_CONCEPT_PROJECT
        case .kernel: return GM_CONCEPT_KERNEL
        }
    }
}
