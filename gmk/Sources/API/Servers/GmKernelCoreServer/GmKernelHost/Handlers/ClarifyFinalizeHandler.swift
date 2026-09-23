import Foundation

/// CLARIFY_FINALIZE — answering → complete; writes refined goal/detail and copies refined_goal into prompt.goal.
enum ClarifyFinalizeHandler {
    /// Handles a CLARIFY_FINALIZE request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The request envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result with the finalize response.
    /// - Throws: Any error from decoding or processing the request.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyFinalizeRequest.self, from: line)
        return try okResult(.clarifyFinalize, head, try store.clarifyFinalize(request))
    }
}
