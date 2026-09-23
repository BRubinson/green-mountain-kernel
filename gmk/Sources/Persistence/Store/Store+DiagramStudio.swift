import Foundation
import GRDB

/// Diagram Studio (v23): the cross-tier browse/search surface and the row
/// delete. Both deliberately live OUTSIDE DiagramListRequest's no-union
/// picker contract — SEARCH is the message that unions tiers, LIST never
/// does. Bodies live in DiagramStudioRepository; these wrappers own the
/// transaction (and the pre-transaction FTS pattern parse).
extension Store {

    // MARK: - Search / browse (the GMVibes gallery backend)

    /// Searches diagrams by query or browses all diagrams.
    ///
    /// - Parameter req: The search request with optional query and filters.
    /// - Returns: The search results with matching diagrams.
    /// - Throws: `StoreError.badRequest` if the visibility or query is invalid.
    func diagramSearch(_ req: DiagramSearchRequest) throws -> DiagramSearchResponse {
        if let visibility = req.visibility, DiagramVisibility(rawValue: visibility) == nil {
            throw StoreError.badRequest(
                detail:
                    "unknown visibility '\(visibility)' (PRIVATE|PUBLIC)"
            )
        }
        let trimmed = (req.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Browse mode tolerates an empty query by design; a NON-empty query
        // that tokenizes to nothing is the nonsense-query BAD_REQUEST the
        // search contract demands (never a silent empty list).
        var pattern: FTS5Pattern?
        if !trimmed.isEmpty {
            // ORs the query tokens (see Store+DopeSearch for why AND was wrong).
            guard let parsed = FTS5Pattern(matchingAnyTokenIn: trimmed) else {
                throw StoreError.badRequest(detail: "search query has no searchable tokens")
            }
            pattern = parsed
        }

        return try boundaryRead { db in
            try DiagramStudioRepository(db: db, core: core).diagramSearch(req, pattern: pattern)
        }
    }

    // MARK: - Delete

    /// Deletes a diagram.
    ///
    /// - Parameter req: The delete request with diagram identifier.
    /// - Returns: The delete response confirming removal.
    /// - Throws: Any store error from the deletion.
    func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        try boundary { db in
            try DiagramStudioRepository(db: db, core: core).diagramDelete(req)
        }
    }
}
