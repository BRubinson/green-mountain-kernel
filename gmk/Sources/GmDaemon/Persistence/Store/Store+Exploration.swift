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

    public func exploreOpen(_ req: ExploreOpenRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).open(req) }
    }

    public func exploreKeyFileAdd(_ req: ExploreKeyFileAddRequest) throws -> ExploreKeyFileAddResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).keyFileAdd(req) }
    }

    public func exploreFindingAdd(_ req: ExploreFindingAddRequest) throws -> ExploreFindingRowResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).findingAdd(req) }
    }

    public func exploreRank(_ req: ExploreRankRequest) throws -> ExploreRankResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).rank(req) }
    }

    public func exploreComplete(_ req: ExploreCompleteRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).complete(req) }
    }

    public func exploreReopen(_ req: ExploreReopenRequest) throws -> ExploreSummaryResponse {
        try boundary { db in try ExplorationRepository(db: db, core: core).reopen(req) }
    }

    public func exploreGet(_ req: ExploreGetRequest) throws -> ExploreGetResponse {
        try boundaryRead { db in try ExplorationRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

    // MARK: - Shared rank/validation helpers (used by Store+Review too)

    /// The GET rating window. full ⇒ unbounded; otherwise [min ?? 0,
    /// max ?? threshold-1]. NULL (unranked) rows are ALWAYS in-window — they
    /// exist only pre-complete and are the ranking agent's work queue; no flag
    /// combination may hide them.
    struct RatingWindow {
        let low: Int
        let high: Int
    }

    /// Validated server-side — the CLI checks too, but vendored wire clients
    /// (GMVibes) reach this without it, and a silently inverted window would
    /// hide findings. `full` excludes bounds; a lone ratingMin widens the
    /// window upward to 999 (never inverts against the default max).
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

    static func ratingInWindow(_ rating: Int?, window: RatingWindow?) -> Bool {
        guard let window else { return true }
        guard let rating else { return true }
        return rating >= window.low && rating <= window.high
    }

    static func validateRating(_ rating: Int?) throws {
        if let rating, !(0...999).contains(rating) {
            throw StoreError.badRequest(detail: "finding_rating must be 0–999 (got \(rating))")
        }
    }

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

    static func normalizedAgentName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

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

    /// Validate then apply one rank batch inside the caller's transaction.
    /// The WHOLE batch validates before any write: non-empty, no duplicate
    /// uuids, every rating 0–999, every finding belonging to this summary
    /// (cross-summary smuggling check) — one bad pair rejects everything.
    /// Rows update via updateBase at their in-transaction current versions
    /// (the clarifyFinalize prompt-version idiom).
    func applyRankBatch(
        _ db: Database,
        table: String,
        parentColumn: String,
        summaryUuid: String,
        ratings: [FindingRating]
    ) throws {
        guard !ratings.isEmpty else {
            throw StoreError.badRequest(detail: "rank batch is empty")
        }
        var seen = Set<String>()
        for pair in ratings {
            guard seen.insert(pair.findingUuid).inserted else {
                throw StoreError.badRequest(detail: "duplicate finding in rank batch: \(pair.findingUuid)")
            }
            guard (0...999).contains(pair.rating) else {
                throw StoreError.badRequest(
                    detail: "finding_rating must be 0–999 (got \(pair.rating) for \(pair.findingUuid))"
                )
            }
            guard
                try Row.fetchOne(
                    db,
                    sql: "SELECT 1 FROM \(table) WHERE uuid = ? AND \(parentColumn) = ?",
                    arguments: [pair.findingUuid, summaryUuid]
                ) != nil
            else {
                throw StoreError.badRequest(
                    detail: "finding \(pair.findingUuid) does not belong to summary \(summaryUuid)"
                )
            }
        }
        for pair in ratings {
            guard
                let version = try Int64.fetchOne(
                    db,
                    sql: "SELECT version FROM \(table) WHERE uuid = ?",
                    arguments: [pair.findingUuid]
                )
            else {
                throw StoreError.notFound(entity: table, key: pair.findingUuid)
            }
            try updateBase(
                db,
                table: table,
                uuid: pair.findingUuid,
                expectedVersion: version,
                set: ["finding_rating": pair.rating]
            )
        }
    }

    func unrankedCount(
        _ db: Database,
        table: String,
        parentColumn: String,
        summaryUuid: String
    ) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(table) WHERE \(parentColumn) = ? AND finding_rating IS NULL",
            arguments: [summaryUuid]
        ) ?? 0
    }
}
