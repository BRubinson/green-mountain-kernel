import Foundation
import GRDB

/// The 0–999 finding-rating write path, shared by ExplorationRepository and
/// ReviewRepository.
///
/// These two methods lived on Store only because two repositories needed them.
/// Under the (db, core) swap that stops being an option: a repository can no
/// longer name a Store, so shared domain logic needs a repository of its own
/// rather than a parking spot on the facade. They are the only genuinely
/// homeless INSTANCE members in the whole extraction — everything else either
/// already had a repository owner or is a static.
///
/// Bodies moved verbatim from Store+Exploration.swift.
struct FindingRankRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Validate then apply one rank batch inside the caller's transaction.
    /// The WHOLE batch validates before any write: non-empty, no duplicate
    /// uuids, every rating 0–999, every finding belonging to this summary
    /// (cross-summary smuggling check) — one bad pair rejects everything.
    /// Rows update via updateBase at their in-transaction current versions
    /// (the clarifyFinalize prompt-version idiom).
    func applyRankBatch(
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
                    detail: "finding_rating must be 0–999 (got \(pair.rating) for \(pair.findingUuid))")
            }
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM \(table) WHERE uuid = ? AND \(parentColumn) = ?",
                arguments: [pair.findingUuid, summaryUuid]
            ) != nil else {
                throw StoreError.badRequest(
                    detail: "finding \(pair.findingUuid) does not belong to summary \(summaryUuid)")
            }
        }
        for pair in ratings {
            guard let version = try Int64.fetchOne(
                db, sql: "SELECT version FROM \(table) WHERE uuid = ?", arguments: [pair.findingUuid]
            ) else {
                throw StoreError.notFound(entity: table, key: pair.findingUuid)
            }
            try core.updateBase(
                db, table: table, uuid: pair.findingUuid,
                expectedVersion: version, set: ["finding_rating": pair.rating])
        }
    }

    func unrankedCount(
        table: String, parentColumn: String, summaryUuid: String
    ) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(table) WHERE \(parentColumn) = ? AND finding_rating IS NULL",
            arguments: [summaryUuid]) ?? 0
    }

    // MARK: - Prompt-scoped (m0025 per-agent exploration summaries)

    /// The cross-summary rank batch: one atomic calibrated batch over every
    /// finding of every exploration summary of ONE prompt (the reranker's
    /// cross-persona tombstone contract, re-keyed from summary to prompt).
    /// Same all-or-nothing validation as applyRankBatch; the membership check
    /// walks the summary join instead of one parent uuid.
    func applyPromptRankBatch(promptUuid: String, ratings: [FindingRating]) throws {
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
                    detail: "finding_rating must be 0–999 (got \(pair.rating) for \(pair.findingUuid))")
            }
            guard try Row.fetchOne(
                db, sql: """
                    SELECT 1 FROM exploration_finding f
                    JOIN exploration_summary s ON s.uuid = f.exploration_summary_uuid
                    WHERE f.uuid = ? AND s.prompt_uuid = ?
                    """,
                arguments: [pair.findingUuid, promptUuid]
            ) != nil else {
                throw StoreError.badRequest(
                    detail: "finding \(pair.findingUuid) does not belong to prompt \(promptUuid)")
            }
        }
        for pair in ratings {
            guard let version = try Int64.fetchOne(
                db, sql: "SELECT version FROM exploration_finding WHERE uuid = ?",
                arguments: [pair.findingUuid]
            ) else {
                throw StoreError.notFound(entity: "exploration_finding", key: pair.findingUuid)
            }
            try core.updateBase(
                db, table: "exploration_finding", uuid: pair.findingUuid,
                expectedVersion: version, set: ["finding_rating": pair.rating])
        }
    }

    /// Unranked findings across ALL of the prompt's exploration summaries —
    /// the synthesis-complete (seal) gate.
    func promptUnrankedCount(promptUuid: String) throws -> Int {
        try Int.fetchOne(
            db, sql: """
                SELECT COUNT(*) FROM exploration_finding f
                JOIN exploration_summary s ON s.uuid = f.exploration_summary_uuid
                WHERE s.prompt_uuid = ? AND f.finding_rating IS NULL
                  AND f.kind != 'key_file'
                """,
            arguments: [promptUuid]) ?? 0
    }
}
