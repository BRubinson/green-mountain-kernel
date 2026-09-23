import Foundation

/// REVIEW_GET — threshold-partitioned read (stubs carry status so the fix loop sees resolution state).
enum ReviewGetHandler {
    /// Handles REVIEW_GET command to fetch code review findings with threshold filtering.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the review findings response.
    /// - Throws: Errors from payload decoding or store access.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewGetRequest.self, from: line)
        return try okResult(.reviewGet, head, try store.reviewGet(request))
    }
}
