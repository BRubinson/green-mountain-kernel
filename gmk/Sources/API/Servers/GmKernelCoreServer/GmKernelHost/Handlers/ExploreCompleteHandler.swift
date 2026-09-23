import Foundation

/// EXPLORE_COMPLETE — exploring → complete; refuses unranked findings; the ONLY write path for overview.
enum ExploreCompleteHandler {
    /// Handles an explore complete request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the completion response.
    /// - Throws: Any error from decoding the request or completing the exploration.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreCompleteRequest.self, from: line)
        return try okResult(.exploreComplete, head, try store.exploreComplete(request))
    }
}
