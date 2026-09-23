import Foundation

/// SESSION_GET — one-shot session context: session row + prompt stubs +
/// change summaries (per-prompt entries stay empty until file changes carry
/// prompt attribution).
enum SessionGetHandler {
    /// Processes a SESSION_GET request and returns the result.
    /// - Parameters:
    ///   - line: The raw request data.
    ///   - head: The message envelope.
    ///   - store: The database store.
    /// - Returns: The handler result with session context and prompt stubs.
    /// - Throws: Decoding or store errors if the request is invalid.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionGetRequest.self, from: line)
        return try okResult(.sessionGet, head, try store.getSession(request))
    }
}
