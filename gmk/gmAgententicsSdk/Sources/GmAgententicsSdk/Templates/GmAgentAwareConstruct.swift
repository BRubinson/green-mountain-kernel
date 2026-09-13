import Foundation

public enum GmAgentAwareConstruct: String, Sendable, Hashable, Codable, CaseIterable {

    case projects

    case cde

    case dope

    case kbite

    case diagram

    case fs

    case system

    public var code: String { rawValue }

    public var description: String {
        switch self {

        case .projects:
            return """
                Identity, and the spine every other row hangs off. A PROJECT is one git \
                repository, named by its root basename. An INSTANCE is one filesystem \
                checkout of it — moving the checkout mints a new instance rather than \
                updating the old one. A SESSION is one git branch inside an instance, and \
                a harness session binds to exactly one. All three are derived from the \
                working directory and the branch, so they are re-derivable and never \
                guessed.
                """

        case .cde:
            return """
                The Context Development Environment starting with a prompt where the work itself is recorded and coordinated.
                """

        case .dope:
            return """
                DOPE — Domain Optimized Project Essence — is the project's model of \
                ITSELF: scopes, persistence domains and their entities, enums and \
                properties, the cogs that describe what the repo is MADE OF rather \
                than what it models.
                """

        case .kbite:
            return """
                knowledge bites often external pre-indexed resources. contains documents, api references, and full example projects/sources
                """

        case .diagram:
            return """
                Structured drawings
                """

        case .fs:
            return """
                A non-hidden filesystem that is used by the kernel based as ~/gmfs
                """

        case .system:
            return """
                Global behaviors and settings
                """
        }
    }

    public var toolFamily: GmAgentToolFamily {
        switch self {
        case .projects: return .projects
        case .cde: return .cde
        case .dope: return .dope
        case .kbite: return .kbite
        case .diagram: return .diagram
        case .fs: return .fs
        case .system: return .system
        }
    }

    public init(_ family: GmAgentToolFamily) {
        switch family {
        case .projects: self = .projects
        case .cde: self = .cde
        case .dope: self = .dope
        case .kbite: self = .kbite
        case .diagram: self = .diagram
        case .fs: self = .fs
        case .system: self = .system
        }
    }

    public static var catalog: String {
        allCases.enumerated()
            .map { "\($0.offset + 1). `\($0.element.code)` ~ \($0.element.description)" }
            .joined(separator: "\n\n")
    }
}
