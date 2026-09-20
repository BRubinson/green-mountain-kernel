import Foundation
import GRDB

// SEARCH — FTS5 full-text search over prompt/clarification/architecture/
// exploration/review text. Eleven external-content mirrors, one SELECT arm per
// requested kind UNIONed, bm25 column-weighted ranking, ranked stubs with prompt
// lineage and a bounded FTS5 snippet as the excerpt.
// SQLite's bm25() returns a NEGATIVE number and the ORDER BY is ascending, so
// more-negative is better and a kind-bias multiplier below 1 DEMOTES that kind.
// Scores stay comparable only WITHIN a kind, so the response exposes kind and
// score rather than selling a unified relevance number.

extension Store {
    public func search(_ req: SearchRequest) throws -> SearchResponse {
        // Deliberate divergence from the kbite precedent: a whitespace-only
        // query is BAD_REQUEST rather than an empty hit list — a silent empty
        // result for a nonsense query is the antipattern the listing
        // contract rejects.
        // ORs the query tokens (see Store+DopeSearch for why AND was wrong).
        guard let pattern = FTS5Pattern(matchingAnyTokenIn: req.query) else {
            throw StoreError.badRequest(detail: "search query has no searchable tokens")
        }
        return try boundaryRead { db in
            try SearchRepository(db: db, core: core).search(req, pattern: pattern)
        }
    }
}
