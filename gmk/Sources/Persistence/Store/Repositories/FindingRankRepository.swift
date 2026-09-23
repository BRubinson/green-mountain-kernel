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

    /// Validates and applies one rank batch inside the caller's transaction.
    ///
    /// The WHOLE batch validates before any write: non-empty, no duplicate uuids,
    /// every rating 0–999, every finding belonging to this summary (cross-summary
    /// smuggling check) — one bad pair rejects everything. Rows update via
    /// updateBase at their in-transaction current versions (the clarifyFinalize
    /// prompt-version idiom).
    ///
    /// - Parameters:
    ///   - type: The finding type being ranked.
    ///   - summaryUuid: The summary uuid; all findings must belong to this summary.
    ///   - ratings: The finding uuids and their 0–999 ratings.
    /// - Throws: `StoreError.badRequest` if the batch is invalid; `StoreError.notFound` if a finding does not exist.
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

    /// Validates a rank batch before processing.
    ///
    /// Checks for non-empty, no duplicate uuids, every rating in range, and
    /// membership via the caller's test.
    ///
    /// - Parameters:
    ///   - ratings: The finding ratings to validate.
    ///   - belongs: A closure that returns true when the finding belongs to the parent.
    ///   - rejection: A closure that produces the error message for a failed member.
    /// - Throws: `StoreError.badRequest` when validation fails.
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
    ///
    /// - Parameters:
    ///   - type: The record type.
    ///   - uuid: The row uuid.
    /// - Returns: The row's version, or nil if not found.
    /// - Throws: Database errors.
    private func currentVersion<T: BaseRecordFields & TableRecord>(
        _ type: T.Type,
        uuid: String
    ) throws -> Int64? {
        try type.all()
            .withUuid(uuid)
            .select(Column("version"), as: Int64.self)
            .fetchOne(db)
    }

    /// The count of unranked findings in a summary.
    ///
    /// - Parameters:
    ///   - type: The finding type.
    ///   - summaryUuid: The summary uuid.
    /// - Returns: The count of unranked findings.
    /// - Throws: Database errors.
    func unrankedCount<T: Rankable & ParentKeyed>(
        _ type: T.Type,
        summaryUuid: String
    ) throws -> Int {
        try type.all().forParent(summaryUuid).unranked().fetchCount(db)
    }

    // MARK: - Prompt-scoped (m0025 per-agent exploration summaries)

    /// Applies a calibrated rank batch across all exploration summaries of one prompt.
    ///
    /// This is the cross-summary rank batch with same all-or-nothing validation as
    /// `applyRankBatch`, but membership checks via the summary join instead of one
    /// parent uuid. It implements the reranker's cross-persona tombstone contract.
    ///
    /// - Parameters:
    ///   - promptUuid: The prompt uuid; all findings must belong to it.
    ///   - ratings: The finding uuids and their 0–999 ratings.
    /// - Throws: `StoreError.badRequest` if the batch is invalid; `StoreError.notFound` if a finding does not exist.
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

    /// The count of unranked findings across all exploration summaries of a prompt.
    ///
    /// Key file findings are path anchors and are excluded. Used as the
    /// synthesis-complete (seal) gate.
    ///
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The count of unranked findings (excluding key file findings).
    /// - Throws: Database errors.
    func promptUnrankedCount(promptUuid: String) throws -> Int {
        try promptFindings(promptUuid)
            .unranked()
            .filter(ExplorationFindingRecord.Columns.kind != ExplorationFindingKind.keyFile.rawValue)
            .fetchCount(db)
    }

    /// Every exploration finding of one prompt, whichever summary carries it.
    ///
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: A query for all findings belonging to the prompt.
    private func promptFindings(_ promptUuid: String) -> QueryInterfaceRequest<ExplorationFindingRecord> {
        ExplorationFindingRecord.joining(
            required: ExplorationFindingRecord.summary
                .filter(Column("prompt_uuid") == promptUuid)
        )
    }
}
