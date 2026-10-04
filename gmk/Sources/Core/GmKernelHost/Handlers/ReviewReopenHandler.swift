import Foundation

/// REVIEW_REOPEN — complete → reviewing revision edge; preserves all data (verdict survives until re-complete).
enum ReviewReopenHandler {
    /// Handles a REVIEW_REOPEN request.
    ///
    /// - Parameters:
    ///   - line: The NDJSON line containing the request.
    ///   - head: The envelope head with protocol version and request id.
    ///   - store: The store to update the review in.
    /// - Returns: The handler result with the reopen response.
    /// - Throws: Decoding errors or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewReopenRequest.self, from: line)
        return try okResult(.reviewReopen, head, try store.reviewReopen(request))
    }
}
