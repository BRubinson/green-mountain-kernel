import Foundation

/// PROMPT_CREATE — atomically allocates the next per-session seq (replaces
/// the max-id+1 yaml scan), inserts the prompt row with seeded
/// prompt_active_kbite links.
///
/// Db only — no yaml write-through.
enum PromptCreateHandler {
    /// Handles a PROMPT_CREATE verb request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope head with verb and session info.
    ///   - store: The store to execute the request against.
    /// - Returns: The handler result with the response.
    /// - Throws: Validation or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptCreateRequest.self, from: line)
        return try okResult(.promptCreate, head, try store.createPrompt(request))
    }
}
