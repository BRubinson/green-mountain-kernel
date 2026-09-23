import Foundation

/// Payload identifying a session for the session route (`Route.session`).
///
/// Plain synthesized value semantics: one-window-per-session dedupe would be concurrency
/// control, which belongs to `SessionScopeCache`. A uuid-only payload, because every
/// filesystem location is derived at render time from daemon rows via `GmFsPathResolver`.
struct SessionWindowID: Codable, Hashable, Identifiable {
    let sessionUUID: UUID
    let instanceUUID: UUID
    let sessionName: String
    /// The prompt identity for `Route.sessionPrompt` (nil degrades to the
    /// newest-prompt rule).
    ///
    /// `var` + Optional: memberwise init defaults to nil, synthesized Codable uses decodeIfPresent
    /// (PromptMemoriesWindowID contract). DIFFERENT prompt changes route identity and re-ids window;
    /// SAME target is route-equal and short-circuits. Route IS the deep link.
    var targetPromptUUID: UUID?

    var id: UUID { sessionUUID }
}
