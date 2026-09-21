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
    /// newest-prompt rule). `var` + Optional ⇒ the memberwise init defaults it
    /// to nil and synthesized Codable uses decodeIfPresent (the
    /// PromptMemoriesWindowID contract).
    ///
    /// Part of Hashable: targeting a DIFFERENT prompt changes route identity and re-ids the
    /// window content, while a repeat hit with the SAME target is route-equal and
    /// `WindowNav.go` short-circuits. The route IS the deep link.
    var targetPromptUUID: UUID?

    var id: UUID { sessionUUID }
}
