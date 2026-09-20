// The typed error surface every agent tool throws through.

import Foundation

enum GmAgentToolError: Error, Sendable {

    case notSupported(tool: String, detail: String)

    case notImplemented(family: GmAgentToolFamily)

    case ambiguousSelector(selector: String, candidates: [String])

    case notWired(tool: String, verb: String)
}

extension GmAgentToolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSupported(let tool, let detail):
            return "\(tool) is declared but not backed by a daemon verb: \(detail)"
        case .notImplemented(let family):
            return """
                the \(family.rawValue) tool family is a declared placeholder \
                with no implementation yet
                """
        case .ambiguousSelector(let selector, let candidates):
            return """
                '\(selector)' matches \(candidates.count) prompts \
                (\(candidates.joined(separator: ", "))) — pick one rather than \
                re-running the same selector
                """
        case .notWired(let tool, let verb):
            return "\(tool) is staged but not wired; it will send \(verb)"
        }
    }
}
