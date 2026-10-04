import Foundation
import GRDB

// CATALOG_SEARCH — tokenized OR name/code search across instances + sessions,
// the GMVibes per-project search bar. Read-only; no daemon_event rows. Matching
// mirrors GMVibes' SearchQuery.matchesAny: split on whitespace, a row matches
// if ANY token is a case-insensitive literal substring of its name OR code
// (LIKE wildcards in tokens are escaped). An instance match pulls in ALL its
// sessions (ancestor-match ⇒ whole subtree); every returned session's parent
// instance rides along so the client can group without a second call.
// Bodies live in CatalogSearchRepository; this wrapper owns the transaction.

extension Store {
    /// Searches the catalog by name and code across all projects.
    ///
    /// - Parameter req: The search request with query and limit.
    /// - Returns: The matching instances and sessions.
    /// - Throws: Any error from the repository.
    func searchCatalog(_ req: CatalogSearchRequest) throws -> CatalogSearchResponse {
        let tokens = req.query
            .split(whereSeparator: \.isWhitespace)
            .map { Self.escapeLikeToken(String($0)) }
        guard !tokens.isEmpty else {
            throw StoreError.badRequest(detail: "search query is empty")
        }
        let limit = min(max(req.limit ?? 200, 1), 1_000)
        return try boundaryRead { db in
            try CatalogSearchRepository(db: db, core: core)
                .searchCatalog(req, tokens: tokens, limit: limit)
        }
    }

    /// Escapes LIKE wildcards in a token for literal substring matching.
    ///
    /// The escape character itself is replaced first to prevent double-escaping.
    ///
    /// - Parameter token: The token to escape.
    /// - Returns: The token with LIKE wildcards escaped.
    private static func escapeLikeToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
