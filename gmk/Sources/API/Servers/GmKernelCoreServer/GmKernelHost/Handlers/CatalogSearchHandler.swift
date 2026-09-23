import Foundation

/// CATALOG_SEARCH — tokenized OR name/code search over instances + sessions,
/// optionally scoped to one project.
enum CatalogSearchHandler {
    /// Handles a catalog search request.
    ///
    /// - Parameters:
    ///   - line: The encoded request data.
    ///   - head: The envelope header containing request metadata.
    ///   - store: The storage layer for catalog access.
    /// - Returns: The handler result with the search response.
    /// - Throws: Any error from decoding or searching the catalog.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CatalogSearchRequest.self, from: line)
        return try okResult(.catalogSearch, head, try store.searchCatalog(request))
    }
}
