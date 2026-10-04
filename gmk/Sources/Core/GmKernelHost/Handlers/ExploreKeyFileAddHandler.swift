import Foundation

/// EXPLORE_KEY_FILE_ADD — add one key file to the shared deduped set (duplicate path = idempotent upsert-ignore).
enum ExploreKeyFileAddHandler {
    /// Handle an EXPLORE_KEY_FILE_ADD request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The persistence store.
    /// - Returns: A `HandlerResult` containing the encoded response.
    /// - Throws: `HandlerError` if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreKeyFileAddRequest.self, from: line)
        return try okResult(.exploreKeyFileAdd, head, try store.exploreKeyFileAdd(request))
    }
}
