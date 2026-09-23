import Foundation

/// SESSION_UPDATE — optimistic-concurrency guarded partial update of
/// session-owned scalars (name, backstory, goal, status active|closed).
enum SessionUpdateHandler {
    /// Handles SESSION_UPDATE requests.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The kernel data store.
    /// - Returns: The handler result with the response.
    /// - Throws: An error if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionUpdateRequest.self, from: line)
        return try okResult(.sessionUpdate, head, try store.updateSession(request))
    }
}
