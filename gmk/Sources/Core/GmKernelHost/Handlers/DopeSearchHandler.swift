import Foundation

/// DOPE_SEARCH — full-text over the dope tree at prompt/session/project scope.
enum DopeSearchHandler {
    /// Handles a dope search request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The main store.
    /// - Returns: The handler result.
    /// - Throws: Errors from decoding or store operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeSearchRequest.self, from: line)
        return try okResult(.dopeSearch, head, try store.dopeSearch(req))
    }
}
