import Foundation
import GRDB

/// The two phase-exit contracts: what "implementation is finished" and "the review fix loop
/// is finished" mean in db evidence.
///
/// ADVISORY ONLY. Appended to blockers prefixed `advisory: `. Do not move into entryBlockers:
/// an entry blocker on `.done` would derive an already-done prompt backwards to `.reviewFix`.
/// On hot path (from `FileChangeRepository.add`), so opt-in.
enum WorkflowGates {

    /// Returns unmet conditions blocking transition from IMPLEMENT to REVIEW.
    ///
    /// The IMPLEMENT exit contract, read as REVIEW's entry contract.
    /// Three questions against the plan of record: every planned persistence
    /// change has at least one recorded `file_change` against its path;
    /// persistence-first ordering was not violated, where `nil` passes
    /// vacuously; and the plan carries general change rows while the prompt
    /// recorded NO file changes at all. That last one stops the predicate being
    /// vacuous for every plan with no persistence changes. Empty = nothing to say.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - promptUuid: The prompt uuid to check.
    /// - Returns: Array of human-readable unmet condition descriptions.
    /// - Throws: Database errors from queries.
    static func implementExitUnmet(_ db: Database, promptUuid: String) throws -> [String] {
        var unmet: [String] = []

        // (1) planned persistence paths with no file_change row.
        let change = TableAlias<ArchitecturePersistenceChangeRecord>(name: "pc")
        let untouchedPersistence =
            try ArchitecturePersistenceChangeRecord
            .aliased(change)
            .joining(
                required: ArchitecturePersistenceChangeRecord.summary
                    .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
            )
            .filter(
                sql: """
                    NOT EXISTS (
                        SELECT 1 FROM file_change fc
                        JOIN session_file sf ON sf.uuid = fc.session_file_uuid
                        WHERE fc.prompt_uuid = ?
                          AND sf.relative_path = pc.file_path)
                    """,
                arguments: [promptUuid]
            )
            .fetchCount(db)
        if untouchedPersistence > 0 {
            unmet.append(
                "\(untouchedPersistence) planned persistence change(s) have no recorded "
                    + "file change (the edit never happened, or the plan is stale)"
            )
        }

        // (2) persistence-first ordering, same rule as ARCH_GET: the LAST
        // persistence path to be first touched must not be later than the
        // FIRST general path to be first touched. Either side empty ⇒ vacuous.
        let persistenceLatestFirstTouch = try String.fetchOne(
            db,
            sql: """
                SELECT MAX(first_touch) FROM (
                    SELECT MIN(fc.created_at) AS first_touch
                    FROM architecture_persistence_change pc
                    JOIN architecture_summary s ON s.uuid = pc.architecture_summary_uuid
                    JOIN session_file sf ON sf.relative_path = pc.file_path
                    JOIN file_change fc ON fc.session_file_uuid = sf.uuid
                    WHERE s.prompt_uuid = ? AND fc.prompt_uuid = s.prompt_uuid
                    GROUP BY pc.file_path)
                """,
            arguments: [promptUuid]
        )
        let generalEarliestFirstTouch = try String.fetchOne(
            db,
            sql: """
                SELECT MIN(fc.created_at)
                FROM architecture_general_change gc
                JOIN architecture_summary s ON s.uuid = gc.architecture_summary_uuid
                JOIN session_file sf ON sf.relative_path = gc.file_path
                JOIN file_change fc ON fc.session_file_uuid = sf.uuid
                WHERE s.prompt_uuid = ? AND fc.prompt_uuid = s.prompt_uuid
                """,
            arguments: [promptUuid]
        )
        if let persistenceLatestFirstTouch, let generalEarliestFirstTouch,
            persistenceLatestFirstTouch > generalEarliestFirstTouch
        {
            unmet.append(
                "persistence-first ordering not respected (a general change landed "
                    + "\(generalEarliestFirstTouch), a persistence change only "
                    + "\(persistenceLatestFirstTouch)) — see "
                    + "\(CdeToolSpec.qualifiedName("cde_rpir_architecture")) op get"
            )
        }

        // (3) a plan with general rows and not one recorded change.
        let generalPlanned =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM architecture_general_change gc
                    JOIN architecture_summary s ON s.uuid = gc.architecture_summary_uuid
                    WHERE s.prompt_uuid = ?
                    """,
                arguments: [promptUuid]
            ) ?? 0
        if generalPlanned > 0 {
            let recorded =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM file_change WHERE prompt_uuid = ?",
                    arguments: [promptUuid]
                ) ?? 0
            if recorded == 0 {
                unmet.append(
                    "\(generalPlanned) planned general change(s) and ZERO recorded file "
                        + "changes — the machine can see no implementation at all"
                )
            }
        }

        return unmet
    }

    /// Returns unmet conditions blocking transition from REVIEW_FIX to DONE.
    ///
    /// The REVIEW_FIX exit contract, read as DONE's entry contract: no open
    /// finding rated below the read threshold (0 = critical, 999 = tombstone,
    /// 100 = the read threshold — the polarity is inverted from the retired
    /// 1-8 scale).
    ///
    /// Unranked findings carry a NULL rating and are deliberately not counted
    /// here; ranking them is the review rank pass's job, and a prompt cannot
    /// reach review_fix without the review being complete. Empty = nothing to say.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - promptUuid: The prompt uuid to check.
    /// - Returns: Array of human-readable unmet condition descriptions.
    /// - Throws: Database errors from queries.
    static func reviewFixExitUnmet(_ db: Database, promptUuid: String) throws -> [String] {
        let open =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM review_finding f
                    JOIN review_summary s ON s.uuid = f.review_summary_uuid
                    WHERE s.prompt_uuid = ?
                      AND f.finding_rating IS NOT NULL
                      AND f.finding_rating < 100
                      AND f.status = 'open'
                    """,
                arguments: [promptUuid]
            ) ?? 0
        guard open > 0 else { return [] }
        return [
            "\(open) open finding(s) rated below 100 — resolve them (REVIEW_RESOLVE) "
                + "or rank them out"
        ]
    }
}
