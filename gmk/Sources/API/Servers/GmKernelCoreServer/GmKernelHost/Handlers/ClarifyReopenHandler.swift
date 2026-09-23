import Foundation

/// CLARIFY_REOPEN — complete → answering, the revision edge.
enum ClarifyReopenHandler {
    /// Handles a clarify reopen request to transition from complete to answering.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the response.
    /// - Throws: A handler error if the request is invalid or the operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyReopenRequest.self, from: line)
        return try okResult(.clarifyReopen, head, try store.clarifyReopen(request))
    }
}
