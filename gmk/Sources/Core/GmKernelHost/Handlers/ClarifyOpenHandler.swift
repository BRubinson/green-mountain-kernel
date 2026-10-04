import Foundation

/// CLARIFY_OPEN — idempotent create-or-return of the clarification summary.
///
/// Never transitions the prompt: status has a single front door elsewhere.
enum ClarifyOpenHandler {
    /// Handles a clarify-open request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the response.
    /// - Throws: Any decoding or store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyOpenRequest.self, from: line)
        return try okResult(.clarifyOpen, head, try store.clarifyOpen(request))
    }
}
