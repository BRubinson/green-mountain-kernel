import Foundation
import GRDB

/// The 0–999 finding-rating write path, shared by ExplorationRepository and
/// ReviewRepository.
///
/// It is a repository of its own because a repository cannot name a Store under
/// the (db, core) swap, so shared domain logic needs an owner rather than a
/// parking spot on the facade.
struct FindingRankRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Validate then apply one rank batch inside the caller's transaction.
    /// The WHOLE batch validates before any write: non-empty, no duplicate
    /// uuids, every rating 0–999, every finding belonging to this summary
    /// (cross-summary smuggling check) — one bad pair rejects everything.
    /// Rows update via updateBase at their in-transaction current versions
    /// (the clarifyFinalize prompt-version idiom).
    func applyRankBatch<T: BaseRecordFields & Rankable & ParentKeyed>(
        _ type: T.Type,
        summaryUuid: String,
        ratings: [FindingRating]
    ) throws {
        try validate(ratings) { findingUuid in
            try type.all().forParent(summaryUuid).withUuid(findingUuid).fetchCount(db) > 0
        } rejection: { findingUuid in
            "finding \(findingUuid) does not belong to summary \(summaryUuid)"
        }
        for pair in ratings {
            guard let version = try currentVersion(type, uuid: pair.findingUuid) else {
                throw StoreError.notFound(entity: T.databaseTableName, key: pair.findingUuid)
            }
            try core.updateBase(
                db,
                table: T.databaseTableName,
                uuid: pair.findingUuid,
                expectedVersion: version,
                set: ["finding_rating": pair.rating]
            )
        }
    }

    /// The shared pre-flight: non-empty, no duplicate uuid, every rating in
    /// range, and each finding accepted by the caller's membership test.
    private func validate(
        _ ratings: [FindingRating],
        belongs: (String) throws -> Bool,
        rejection: (String) -> String
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
            guard try belongs(pair.findingUuid) else {
                throw StoreError.badRequest(detail: rejection(pair.findingUuid))
            }
        }
    }

    /// The row's version as the transaction currently sees it, for updateBase.
    private func currentVersion<T: BaseRecordFields & TableRecord>(
        _ type: T.Type,
        uuid: String
    ) throws -> Int64? {
        try type.all()
            .withUuid(uuid)
            .select(Column("version"), as: Int64.self)
            .fetchOne(db)
    }

    /// The unranked findings of one summary, for the caller's completion gate.
    func unrankedCount<T: Rankable & ParentKeyed>(
        _ type: T.Type,
        summaryUuid: String
    ) throws -> Int {
        try type.all().forParent(summaryUuid).unranked().fetchCount(db)
    }

    // MARK: - Prompt-scoped (m0025 per-agent exploration summaries)

    /// The cross-summary rank batch: one atomic calibrated batch over every
    /// finding of every exploration summary of ONE prompt (the reranker's
    /// cross-persona tombstone contract, re-keyed from summary to prompt).
    /// Same all-or-nothing validation as applyRankBatch; the membership check
    /// walks the summary join instead of one parent uuid.
    func applyPromptRankBatch(promptUuid: String, ratings: [FindingRating]) throws {
        try validate(ratings) { findingUuid in
            try promptFindings(promptUuid).withUuid(findingUuid).fetchCount(db) > 0
        } rejection: { findingUuid in
            "finding \(findingUuid) does not belong to prompt \(promptUuid)"
        }
        for pair in ratings {
            guard
                let version = try currentVersion(ExplorationFindingRecord.self, uuid: pair.findingUuid)
            else {
                throw StoreError.notFound(entity: "exploration_finding", key: pair.findingUuid)
            }
            try core.updateBase(
                db,
                table: "exploration_finding",
                uuid: pair.findingUuid,
                expectedVersion: version,
                set: ["finding_rating": pair.rating]
            )
        }
    }

    /// Unranked findings across ALL of the prompt's exploration summaries —
    /// the synthesis-complete (seal) gate. key_file findings are path anchors,
    /// never ranked.
    func promptUnrankedCount(promptUuid: String) throws -> Int {
        try promptFindings(promptUuid)
            .unranked()
            .filter(ExplorationFindingRecord.Columns.kind != ExplorationFindingKind.keyFile.rawValue)
            .fetchCount(db)
    }

    /// Every exploration finding of one prompt, whichever summary carries it.
    private func promptFindings(_ promptUuid: String) -> QueryInterfaceRequest<ExplorationFindingRecord> {
        ExplorationFindingRecord.joining(
            required: ExplorationFindingRecord.summary
                .filter(Column("prompt_uuid") == promptUuid)
        )
    }
}
