import Foundation

/// KBITE_SEARCH — FTS5 ranked stubs, optionally scoped by kbite_uuids.
enum KbiteSearchHandler {
    /// Handles a kbite search request.
    ///
    /// - Parameters:
    ///   - line: The wire data containing the search request.
    ///   - head: The envelope metadata.
    ///   - store: The store to perform the search on.
    /// - Returns: The handler result with the search response.
    /// - Throws: Errors if decoding or the search operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteSearchRequest.self, from: line)
        return try okResult(.kbiteSearch, head, try store.searchKbites(request))
    }
}
