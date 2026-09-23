import Foundation

/// EXPLORE_REOPEN — complete → exploring revision edge; preserves all data.
enum ExploreReopenHandler {
    /// Handles an exploration reopening request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the reopen response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreReopenRequest.self, from: line)
        return try okResult(.exploreReopen, head, try store.exploreReopen(request))
    }
}
