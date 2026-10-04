import Foundation

/// EXPLORE_FINDING_ADD — insert a finding (rating optional; NULL = unranked work-in-progress).
enum ExploreFindingAddHandler {
    /// Handles an exploreFindingAdd request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreFindingAddRequest.self, from: line)
        return try okResult(.exploreFindingAdd, head, try store.exploreFindingAdd(request))
    }
}
