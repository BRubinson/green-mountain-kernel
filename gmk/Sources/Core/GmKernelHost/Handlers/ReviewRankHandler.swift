import Foundation

/// REVIEW_RANK — atomic version-less batch rank (same contract as EXPLORE_RANK).
enum ReviewRankHandler {
    /// Handles a REVIEW_RANK request to rank review findings.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header with request metadata.
    ///   - store: The store to execute the ranking operation.
    /// - Returns: The handler result with response data.
    /// - Throws: Any error during request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewRankRequest.self, from: line)
        return try okResult(.reviewRank, head, try store.reviewRank(request))
    }
}
