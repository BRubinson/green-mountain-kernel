import Foundation
import GRDB

/// SEARCH data access — FTS5 UNION over the bot-report mirrors. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
struct SearchRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func search(_ req: SearchRequest, pattern: FTS5Pattern) throws -> SearchResponse {
        if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
        }
        let limit = min(max(req.limit ?? 50, 1), 500)
        let kinds = (req.kinds?.isEmpty ?? true) ? SearchKind.allCases : req.kinds!
        var arms: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        let scope = req.sessionUuid == nil ? "" : " AND p.session_uuid = ?"
        for kind in kinds {
            arms.append(Self.searchArm(for: kind, scope: scope))
            arguments.append(pattern)
            if let sessionUuid = req.sessionUuid { arguments.append(sessionUuid) }
        }
        let sql = arms.joined(separator: "\nUNION ALL\n")
            + "\nORDER BY score LIMIT \(limit)"
        return SearchResponse(hits: try Row.fetchAll(
            db, sql: sql, arguments: StatementArguments(arguments)
        ).map { row in
            SearchHit(
                kind: row["kind"],
                subjectUuid: row["subject_uuid"],
                promptUuid: row["prompt_uuid"],
                promptSeq: row["prompt_seq"],
                promptName: row["prompt_name"],
                promptStatus: row["prompt_status"],
                sessionUuid: row["session_uuid"],
                sessionCode: row["session_code"],
                title: row["title"],
                excerpt: row["excerpt"],
                score: row["score"]
            )
        })
    }

    /// One UNION arm per kind. Every arm produces the identical column list;
    /// lineage joins run child → summary → prompt → session. Weights (higher
    /// = stronger contribution) and the per-kind bias are fixed here —
    /// keeping a 2 MB change_code hit from outranking a direct goal match.
    private static func searchArm(for kind: SearchKind, scope: String) -> String {
        let common = """
            p.uuid AS prompt_uuid, p.seq AS prompt_seq, p.name AS prompt_name,
            p.status AS prompt_status, s.uuid AS session_uuid, s.code AS session_code
            """
        switch kind {
        case .prompt:
            return """
                SELECT 'prompt' AS kind, p.uuid AS subject_uuid, \(common),
                       p.name AS title,
                       snippet(prompt_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(prompt_fts, 10.0, 6.0, 3.0, 1.0) * 1.0 AS score
                FROM prompt_fts fts
                JOIN prompt p ON p.id = fts.rowid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE prompt_fts MATCH ?\(scope)
                """
        case .clarificationQuestion:
            return """
                SELECT 'clarification_question' AS kind, q.uuid AS subject_uuid, \(common),
                       q.question AS title,
                       snippet(user_clarification_question_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(user_clarification_question_fts, 6.0, 4.0) * 0.85 AS score
                FROM user_clarification_question_fts fts
                JOIN user_clarification_question q ON q.id = fts.rowid
                JOIN clarification_summary cs ON cs.uuid = q.clarification_summary_uuid
                JOIN prompt p ON p.uuid = cs.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE user_clarification_question_fts MATCH ?\(scope)
                """
        case .clarificationNote:
            return """
                SELECT 'clarification_note' AS kind, n.uuid AS subject_uuid, \(common),
                       'internal note' AS title,
                       snippet(internal_clarification_note_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(internal_clarification_note_fts, 5.0) * 0.85 AS score
                FROM internal_clarification_note_fts fts
                JOIN internal_clarification_note n ON n.id = fts.rowid
                JOIN clarification_summary cs ON cs.uuid = n.clarification_summary_uuid
                JOIN prompt p ON p.uuid = cs.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE internal_clarification_note_fts MATCH ?\(scope)
                """
        case .architectureSummary:
            return """
                SELECT 'architecture_summary' AS kind, a.uuid AS subject_uuid, \(common),
                       'architecture summary' AS title,
                       snippet(architecture_summary_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(architecture_summary_fts, 5.0) * 0.85 AS score
                FROM architecture_summary_fts fts
                JOIN architecture_summary a ON a.id = fts.rowid
                JOIN prompt p ON p.uuid = a.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE architecture_summary_fts MATCH ?\(scope)
                """
        case .architectureGeneralChange:
            return """
                SELECT 'architecture_general_change' AS kind, gc.uuid AS subject_uuid, \(common),
                       gc.file_path AS title,
                       snippet(architecture_general_change_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(architecture_general_change_fts, 8.0, 5.0, 1.0) * 0.7 AS score
                FROM architecture_general_change_fts fts
                JOIN architecture_general_change gc ON gc.id = fts.rowid
                JOIN architecture_summary a ON a.uuid = gc.architecture_summary_uuid
                JOIN prompt p ON p.uuid = a.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE architecture_general_change_fts MATCH ?\(scope)
                """
        case .architecturePersistenceChange:
            return """
                SELECT 'architecture_persistence_change' AS kind, pc.uuid AS subject_uuid, \(common),
                       pc.file_path AS title,
                       snippet(architecture_persistence_change_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(architecture_persistence_change_fts, 8.0, 8.0, 5.0) * 0.7 AS score
                FROM architecture_persistence_change_fts fts
                JOIN architecture_persistence_change pc ON pc.id = fts.rowid
                JOIN architecture_summary a ON a.uuid = pc.architecture_summary_uuid
                JOIN prompt p ON p.uuid = a.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE architecture_persistence_change_fts MATCH ?\(scope)
                """
        case .explorationSummary:
            return """
                SELECT 'exploration_summary' AS kind, es.uuid AS subject_uuid, \(common),
                       'exploration overview' AS title,
                       snippet(exploration_summary_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(exploration_summary_fts, 5.0) * 0.85 AS score
                FROM exploration_summary_fts fts
                JOIN exploration_summary es ON es.id = fts.rowid
                JOIN prompt p ON p.uuid = es.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE exploration_summary_fts MATCH ?\(scope)
                """
        case .explorationFinding:
            return """
                SELECT 'exploration_finding' AS kind, ef.uuid AS subject_uuid, \(common),
                       ef.title AS title,
                       snippet(exploration_finding_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(exploration_finding_fts, 6.0, 4.0) * 0.7 AS score
                FROM exploration_finding_fts fts
                JOIN exploration_finding ef ON ef.id = fts.rowid
                JOIN exploration_summary es ON es.uuid = ef.exploration_summary_uuid
                JOIN prompt p ON p.uuid = es.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE exploration_finding_fts MATCH ?\(scope)
                """
        case .reviewSummary:
            return """
                SELECT 'review_summary' AS kind, rs.uuid AS subject_uuid, \(common),
                       'review overview' AS title,
                       snippet(review_summary_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(review_summary_fts, 5.0) * 0.85 AS score
                FROM review_summary_fts fts
                JOIN review_summary rs ON rs.id = fts.rowid
                JOIN prompt p ON p.uuid = rs.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE review_summary_fts MATCH ?\(scope)
                """
        case .reviewFinding:
            return """
                SELECT 'review_finding' AS kind, rf.uuid AS subject_uuid, \(common),
                       rf.title AS title,
                       snippet(review_finding_fts, -1, '', '', '…', 24) AS excerpt,
                       bm25(review_finding_fts, 6.0, 4.0, 1.0) * 0.7 AS score
                FROM review_finding_fts fts
                JOIN review_finding rf ON rf.id = fts.rowid
                JOIN review_summary rs ON rs.uuid = rf.review_summary_uuid
                JOIN prompt p ON p.uuid = rs.prompt_uuid
                JOIN session s ON s.uuid = p.session_uuid
                WHERE review_finding_fts MATCH ?\(scope)
                """
        }
    }
}
