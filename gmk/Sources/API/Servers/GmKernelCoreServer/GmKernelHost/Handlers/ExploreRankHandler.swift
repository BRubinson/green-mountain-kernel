import Foundation

/// EXPLORE_RANK — atomic version-less batch rank (whole batch validates before any write).
enum ExploreRankHandler {
    /// Handles EXPLORE_RANK requests.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The kernel data store.
    /// - Returns: The handler result with the response.
    /// - Throws: An error if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreRankRequest.self, from: line)
        return try okResult(.exploreRank, head, try store.exploreRank(request))
    }
}
