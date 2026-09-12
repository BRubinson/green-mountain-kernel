import Foundation

/// Payload identifying a session for the session route (`Route.session`).
/// Plain value semantics: the old hand-written `==`/`hash` keyed on
/// `sessionUUID` alone existed to make `WindowGroup(for:)` dedupe to one
/// window per session — that dedupe was doing concurrency control, a job that
/// now belongs to `SessionScopeCache`, so the override is deliberately gone.
///
/// uuid-only payload: all filesystem locations are derived at render time from
/// daemon rows via CkfsPathResolver.
struct SessionWindowID: Codable, Hashable, Identifiable {
    let sessionUUID: UUID
    let instanceUUID: UUID
    let sessionName: String
    /// The prompt identity for `Route.sessionPrompt` (nil degrades to the
    /// newest-prompt rule). `var` + Optional ⇒ the memberwise init defaults it
    /// to nil and synthesized Codable uses decodeIfPresent (the
    /// PromptMemoriesWindowID contract).
    ///
    /// Part of Hashable: targeting a DIFFERENT prompt changes route identity
    /// and re-ids the window content (cheap via SessionScopeCache's grace
    /// list plus the window-root lease); a repeat hit with the SAME target is
    /// route-equal and `WindowNav.go` short-circuits. The route IS the deep
    /// link — the old one-shot pending channel is gone.
    var targetPromptUUID: UUID?

    var id: UUID { sessionUUID }
}
