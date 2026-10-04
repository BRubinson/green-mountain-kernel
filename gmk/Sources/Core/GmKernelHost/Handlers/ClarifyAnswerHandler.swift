import Foundation

/// CLARIFY_ANSWER — answer or skip one clarification row (summary must be answering); pure row update.
enum ClarifyAnswerHandler {
    /// Handles a clarification answer request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The kernel store.
    /// - Returns: The handler result.
    /// - Throws: `HandlerError` on request failure.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyAnswerRequest.self, from: line)
        return try okResult(.clarifyAnswer, head, try store.clarifyAnswer(request))
    }
}
