import Foundation

/// ARCH_SUMMARIZE — set the concept-level body (drafting only).
enum ArchSummarizeHandler {
    /// Handles the ARCH_SUMMARIZE wire request.
    ///
    /// Sets the concept-level body during drafting. Available only during the
    /// drafting phase; architecture must first be opened.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the summarize response.
    /// - Throws: Errors from decoding or summarize operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchSummarizeRequest.self, from: line)
        return try okResult(.archSummarize, head, try store.archSummarize(request))
    }
}
