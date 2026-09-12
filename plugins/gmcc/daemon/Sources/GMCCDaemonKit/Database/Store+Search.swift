import Foundation
import GRDB

// SEARCH — FTS5 full-text search over prompt/clarification/architecture/
// exploration/review text (the B3 counterpart of KBITE_SEARCH). Eleven
// external-content mirrors (six from m0003, five from m0004), one SELECT arm
// per requested kind UNIONed, bm25 column-weighted ranking, ranked stubs with
// prompt lineage — never full content (the excerpt is a bounded FTS5
// snippet).
//
// Scores: SQLite's bm25() returns a NEGATIVE number and the ORDER BY is
// ascending, so more-negative = better — a kind-bias multiplier < 1 moves a
// score toward zero, i.e. DEMOTES that kind. Scores stay comparable only
// WITHIN a kind; the response exposes kind and score so the caller sees the
// mix rather than being sold a unified relevance number.
//
// Bodies live in SearchRepository; this wrapper owns the transaction (and the
// pre-transaction FTS pattern parse).

extension Store {
    public func search(_ req: SearchRequest) throws -> SearchResponse {
        // Deliberate divergence from the kbite precedent: a whitespace-only
        // query is BAD_REQUEST rather than an empty hit list — a silent empty
        // result for a nonsense query is the antipattern the listing
        // contract rejects.
        guard let pattern = FTS5Pattern(matchingAllTokensIn: req.query) else {
            throw StoreError.badRequest(detail: "search query has no searchable tokens")
        }
        return try dbQueue.read { db in
            try SearchRepository(db: db, core: core).search(req, pattern: pattern)
        }
    }
}
