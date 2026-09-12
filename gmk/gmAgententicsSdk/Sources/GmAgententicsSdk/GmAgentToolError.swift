import Foundation

/// What a tool in this surface throws.
///
/// THE POINT OF A TYPED REFUSAL. Several tools here are declared over daemon
/// verbs that do not exist yet, and three whole families are placeholders. The
/// alternative to declaring them was leaving them out — and leaving them out is
/// worse for a model-facing surface, because an absent tool teaches the model to
/// go find another route (shell, a different verb, a guess), while a present one
/// that refuses teaches it the capability is planned and not yet reachable.
///
/// The rule every case here exists to enforce: **never return an empty success.**
/// An unimplemented tool that returns `[]` is indistinguishable from a real
/// empty result, and will be believed. Every one of these is a throw.
@available(GmAgentOs 1.0, *)
public enum GmAgentToolError: Error, Sendable {
    /// The tool is declared, but the daemon verb behind it does not exist or
    /// cannot express what the tool promises.
    ///
    /// `detail` must name the specific gap — which verb is missing, which field
    /// is absent, which enum arm has no case — because that string is what the
    /// next person wiring this reads, and "not supported" alone sends them back
    /// to rediscover what this package already knows.
    case notSupported(tool: String, detail: String)

    /// The whole family is a declared placeholder with no implementation yet.
    case notImplemented(family: GmAgentToolFamily)

    /// A selector matched more than one prompt.
    ///
    /// Its own case rather than a flavour of `notSupported` because it is not a
    /// gap — it is a RESULT, and the candidates are the answer. `PromptResolver`
    /// is explicit about why this must never collapse into a guess: silently
    /// picking the first would file a session's work against the wrong prompt,
    /// and the append-only db makes that permanent.
    case ambiguousSelector(selector: String, candidates: [String])

    /// The tool is declared and backed, but has not been wired to the daemon
    /// yet. The state every tool in this package is in today.
    case notWired(tool: String, verb: String)
}

@available(GmAgentOs 1.0, *)
extension GmAgentToolError: LocalizedError {
    public var errorDescription: String? {
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
