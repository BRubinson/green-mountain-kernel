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
    public func searchCatalog(_ req: CatalogSearchRequest) throws -> CatalogSearchResponse {
        let tokens = req.query
            .split(whereSeparator: \.isWhitespace)
            .map { Self.escapeLikeToken(String($0)) }
        guard !tokens.isEmpty else {
            throw StoreError.badRequest(detail: "search query is empty")
        }
        let limit = min(max(req.limit ?? 200, 1), 1_000)
        return try dbQueue.read { db in
            try CatalogSearchRepository(db: db, core: core)
                .searchCatalog(req, tokens: tokens, limit: limit)
        }
    }

    /// Escape LIKE wildcards so tokens match as literal substrings (the escape
    /// char itself first, so escaped wildcards don't get double-escaped).
    private static func escapeLikeToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
