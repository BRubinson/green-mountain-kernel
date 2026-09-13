// Turns a GmAgentPrompt template into a filled FoundationModels Prompt, refusing on unfilled holes.

import Foundation
import FoundationModels

enum AgentSessionAskError: Error, CustomStringConvertible {

    case unfilledHoles(ask: String, missing: [String])

    var description: String {
        switch self {
        case let .unfilledHoles(ask, missing):
            return """
                ask `\(ask)` is missing \(missing.count) parameter(s): \
                \(missing.joined(separator: ", "))
                """
        }
    }
}

@available(GmAgentOs 1.0, *)
extension GmAgentPrompt {

    func nativePrompt(filling parameters: [String: String]) throws -> Prompt {
        let missing = Set(holes).subtracting(parameters.keys).sorted()
        guard missing.isEmpty else {
            throw AgentSessionAskError.unfilledHoles(ask: rawValue, missing: missing)
        }
        return Prompt(text(filling: parameters))
    }
}
