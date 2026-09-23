import Foundation

/// SEARCH — FTS5 ranked stubs with prompt lineage over
/// prompt/clarification/architecture text, optionally session-scoped.
enum SearchHandler {
    /// Handles a search request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing ranked search results.
    /// - Throws: An error if decoding or the search fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SearchRequest.self, from: line)
        return try okResult(.search, head, try store.search(request))
    }
}
