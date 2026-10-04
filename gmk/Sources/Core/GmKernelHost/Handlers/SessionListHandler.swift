import Foundation

/// SESSION_LIST — enumerate sessions, optionally filtered to one instance
/// (read-only; unknown instance uuid ⇒ NOT_FOUND).
enum SessionListHandler {
    /// Handle a SESSION_LIST request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The persistence store.
    /// - Returns: A `HandlerResult` containing the encoded response.
    /// - Throws: `HandlerError` if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionListRequest.self, from: line)
        return try okResult(.sessionList, head, try store.listSessions(request))
    }
}
