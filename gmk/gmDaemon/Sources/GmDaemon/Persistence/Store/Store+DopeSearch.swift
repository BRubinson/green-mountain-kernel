import Foundation
import GRDB
import GmDaemonSdk

// DOPE_SEARCH — full-text over the dope tree at one of three scopes.
// Bodies live in DopeSearchRepository; this wrapper owns the transaction
// (and the pre-transaction FTS pattern parse).
//
// The pattern ORs the query tokens and lets bm25 + LIMIT do the ranking. It
// used to AND them, which meant a caller's whole result set was zeroed by one
// token the corpus did not happen to hold — and callers here write
// natural-language phrases of five to eight tokens, so that was the common
// case rather than the edge one. Do not "restore" matchingAllTokensIn.

extension Store {
    public func dopeSearch(_ req: DopeSearchRequest) throws -> DopeSearchResponse {
        guard let pattern = FTS5Pattern(matchingAnyTokenIn: req.query) else {
            throw StoreError.badRequest(detail: "search query has no searchable tokens")
        }
        return try boundaryRead { db in
            try DopeSearchRepository(db: db, core: core).search(req, pattern: pattern)
        }
    }
}
