import Foundation
import GMCCDaemonKit

/// CATALOG_SEARCH — tokenized OR name/code search over instances + sessions,
/// optionally scoped to one project.
enum CatalogSearchHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(CatalogSearchRequest.self, from: line)
        return try okResult(.catalogSearch, head, try store.searchCatalog(request))
    }
}
