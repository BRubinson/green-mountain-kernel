import Foundation
import GRDB

// EXPLORE_* — the db-native exploration report machine. exploring → complete,
// plus the complete → exploring revision edge, since explore is the most re-run
// report and a re-run updates the same summary. Open is EXPLICIT-only, and
// explore verbs NEVER touch prompt.status.
// finding_rating runs 0 (critical) to 999 (tombstone), read threshold 100, and
// NULL marks an unranked finding: COMPLETE refuses while any NULL remains, and
// GETs return NULL-rated rows in the full partition as the resume work-queue.
// overview is carried ONLY by COMPLETE. Bodies live in ExplorationRepository.

extension Store {

    // MARK: - Verbs

    /// Opens an exploration and returns its initial summary.
    ///
    /// - Parameter req: The exploration open request.
    /// - Returns: The initial exploration summary.
    /// - Throws: Store errors if the request is invalid.
    func exploreOpen(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).open(req) }
    }

    /// Adds a key file to an exploration.
    ///
    /// - Parameter req: The key file add request.
    /// - Returns: The result of adding the key file.
    /// - Throws: Store errors if the request is invalid.
    func exploreKeyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).keyFileAdd(req) }
    }

    /// Adds a finding to an exploration.
    ///
    /// - Parameter req: The finding add request.
    /// - Returns: The added finding row.
    /// - Throws: Store errors if the request is invalid.
    func exploreFindingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).findingAdd(req) }
    }

    /// Ranks findings in an exploration.
    ///
    /// - Parameter req: The rank request.
    /// - Returns: The ranking result.
    /// - Throws: Store errors if the request is invalid.
    func exploreRank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).rank(req) }
    }

    /// Completes an exploration.
    ///
    /// - Parameter req: The complete request.
    /// - Returns: The exploration summary after completion.
    /// - Throws: Store errors if the request is invalid.
    func exploreComplete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).complete(req) }
    }

    /// Reopens a completed exploration.
    ///
    /// - Parameter req: The reopen request.
    /// - Returns: The exploration summary after reopening.
    /// - Throws: Store errors if the request is invalid.
    func exploreReopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).reopen(req) }
    }

    /// Reads an exploration and its findings.
    ///
    /// - Parameter req: The get request.
    /// - Returns: The exploration data.
    /// - Throws: Store errors if the request is invalid.
    func exploreGet(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        try boundaryRead { db in try ExplorationRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

    // MARK: - Shared rank/validation helpers (used by Store+Review too)

    /// The GET rating window.
    ///
    /// Full ⇒ unbounded; otherwise [min ?? 0, max ?? threshold-1]. NULL
    /// (unranked) rows are ALWAYS in-window — they exist only pre-complete and
    /// are the ranking agent's work queue; no flag combination may hide them.
    struct RatingWindow {
        let low: Int
        let high: Int
    }

    /// Computes the rating window bounds for filtering findings.
    ///
    /// Validates server-side to prevent silent inversions from hiding findings.
    /// When `full` is true, bounds are ignored. When `min` is set alone, the
    /// window extends to 999. Otherwise bounds default to 0 and the read threshold.
    ///
    /// - Parameters:
    ///   - full: When true, returns nil (unbounded); requires both `min` and
    ///     `max` to be nil.
    ///   - min: The lower rating bound (0–999), or nil for 0.
    ///   - max: The upper rating bound (0–999), or nil for threshold-1.
    /// - Returns: A `RatingWindow` defining the valid range, or nil if `full`
    ///   is true.
    /// - Throws: `StoreError.badRequest` if bounds are invalid, inverted, or
    ///   outside 0–999.
    static func ratingWindow(full: Bool, min: Int?, max: Int?) throws -> RatingWindow? {
        if full {
            guard min == nil, max == nil else {
                throw StoreError.badRequest(detail: "full excludes rating_min/rating_max")
            }
            return nil
        }
        for bound in [min, max] {
            if let bound, !(0...999).contains(bound) {
                throw StoreError.badRequest(detail: "rating bounds must be 0-999 (got \(bound))")
            }
        }
        let low = min ?? 0
        let high = max ?? (min != nil ? 999 : Store.findingReadThreshold - 1)
        guard low <= high else {
            throw StoreError.badRequest(detail: "rating_min (\(low)) exceeds rating_max (\(high))")
        }
        return RatingWindow(low: low, high: high)
    }

    /// Checks whether a rating falls within a window.
    ///
    /// - Parameters:
    ///   - rating: The rating to check, or nil (always in-window).
    ///   - window: The window bounds, or nil (unbounded).
    /// - Returns: True if the rating is in-window.
    static func ratingInWindow(_ rating: Int?, window: RatingWindow?) -> Bool {
        guard let window else { return true }
        guard let rating else { return true }
        return rating >= window.low && rating <= window.high
    }

    /// Validates that a rating is in the range 0–999.
    ///
    /// - Parameter rating: The rating to validate, or nil (always valid).
    /// - Throws: `StoreError.badRequest` if the rating is outside 0–999.
    static func validateRating(_ rating: Int?) throws {
        if let rating, !(0...999).contains(rating) {
            throw StoreError.badRequest(detail: "finding_rating must be 0–999 (got \(rating))")
        }
    }

    /// Trims and validates finding title, body, and agent name.
    ///
    /// Normalizes the agent name to lowercase with underscores. Enforces that
    /// title and agent name are non-empty, and body is non-empty unless allowed.
    ///
    /// - Parameters:
    ///   - title: The finding title (will be trimmed).
    ///   - body: The finding narrative (will be trimmed).
    ///   - agentName: The agent name (will be normalized).
    ///   - allowEmptyBody: When true, an empty body is allowed; default is false.
    /// - Returns: A tuple of trimmed title, body, and normalized agent name.
    /// - Throws: `StoreError.badRequest` if validation fails or body exceeds
    ///   the maximum narrative byte limit.
    static func validatedFindingText(
        title: String,
        body: String,
        agentName: String,
        allowEmptyBody: Bool = false
    ) throws -> (title: String, body: String, agentName: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalized at write, forward-only (no backfill — history is
        // append-only): the db already carries case-split personas
        // ("Aggressive" vs "aggressive") that fracture per-agent queries.
        let agentName = Store.normalizedAgentName(agentName)
        guard !title.isEmpty else { throw StoreError.badRequest(detail: "finding title is empty") }
        // key_file findings (m0025) are path-anchored with no narrative.
        guard allowEmptyBody || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.badRequest(detail: "finding body is empty")
        }
        guard !agentName.isEmpty else { throw StoreError.badRequest(detail: "agent_name is empty") }
        guard body.utf8.count <= Store.maxNarrativeBytes else {
            throw StoreError.badRequest(
                detail: "finding body exceeds \(Store.maxNarrativeBytes / (1024 * 1024)) MB"
            )
        }
        return (title, body, agentName)
    }

    /// Normalizes an agent name to lowercase with underscores.
    ///
    /// - Parameter raw: The agent name to normalize.
    /// - Returns: The normalized name: trimmed, lowercased, spaces replaced
    ///   with underscores.
    static func normalizedAgentName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Validates an entity overview text for non-empty and size constraints.
    ///
    /// - Parameters:
    ///   - raw: The overview text (will be trimmed).
    ///   - entity: The entity type name, used in error messages.
    /// - Returns: The trimmed overview text.
    /// - Throws: `StoreError.badRequest` if empty or exceeds maximum narrative
    ///   byte limit.
    static func validatedOverview(_ raw: String, entity: String) throws -> String {
        let overview = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty else {
            throw StoreError.badRequest(detail: "\(entity) overview is empty")
        }
        guard overview.utf8.count <= Store.maxNarrativeBytes else {
            throw StoreError.badRequest(
                detail: "\(entity) overview exceeds \(Store.maxNarrativeBytes / (1024 * 1024)) MB"
            )
        }
        return overview
    }

}
