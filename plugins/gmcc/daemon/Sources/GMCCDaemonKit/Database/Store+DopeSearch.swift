import Foundation
import GRDB

// DOPE_SEARCH — full-text over the dope tree at one of three scopes.
// Bodies live in DopeSearchRepository; this wrapper owns the transaction
// (and the pre-transaction FTS pattern parse).

extension Store {
    public func dopeSearch(_ req: DopeSearchRequest) throws -> DopeSearchResponse {
        guard let pattern = FTS5Pattern(matchingAllTokensIn: req.query) else {
            throw StoreError.badRequest(detail: "search query has no searchable tokens")
        }
        return try dbQueue.read { db in
            try DopeSearchRepository(db: db, core: core).search(req, pattern: pattern)
        }
    }
}
