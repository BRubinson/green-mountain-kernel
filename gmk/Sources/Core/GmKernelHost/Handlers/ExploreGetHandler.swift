import Foundation

/// EXPLORE_GET — threshold-partitioned read (full rows under the rating window plus every unranked row; stubs outside).
enum ExploreGetHandler {
    /// Processes an EXPLORE_GET request and returns the result.
    /// - Parameters:
    ///   - line: The raw request data.
    ///   - head: The message envelope.
    ///   - store: The database store.
    /// - Returns: The handler result with exploration findings.
    /// - Throws: Decoding or store errors if the request is invalid.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreGetRequest.self, from: line)
        return try okResult(.exploreGet, head, try store.exploreGet(request))
    }
}
