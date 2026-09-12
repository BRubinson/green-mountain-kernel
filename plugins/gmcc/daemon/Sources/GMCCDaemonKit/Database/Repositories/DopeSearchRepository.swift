import Foundation
import GRDB

/// DOPE_SEARCH data access — full-text over the dope tree at one of three
/// scopes; --only-masks is a post-filter over resolver provenance. Runs
/// INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts.
struct DopeSearchRepository: RepositoryContext {
    let db: Database
    let core: StoreCore


    func search(_ req: DopeSearchRequest, pattern: FTS5Pattern) throws -> DopeSearchResponse {
        let limit = min(max(req.limit ?? 50, 1), 500)
        // 1. Which dope scopes are in range for this search scope?
        let scopes = try searchScopeRows(req: req)
        guard !scopes.isEmpty else { return DopeSearchResponse(hits: []) }
        let scopeUuids = scopes.map(\.uuid)
        let placeholders = scopeUuids.map { _ in "?" }.joined(separator: ", ")

        var arms = [String]()
        var args: [any DatabaseValueConvertible] = []
        for source in DopeSearchSource.allCases {
            arms.append(Self.searchArm(source, scopePlaceholders: placeholders))
            args.append(pattern)
            args.append(contentsOf: scopeUuids)
        }
        let sql = arms.joined(separator: "\nUNION ALL\n")
            + "\nORDER BY score LIMIT \(limit)"

        var hits = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            .map { row in
                DopeSearchHit(
                    kind: row["kind"], subjectUuid: row["subject_uuid"],
                    scopeUuid: row["scope_uuid"], scopeCode: row["scope_code"],
                    scopeType: row["scope_type"], path: row["path"],
                    title: row["title"], excerpt: row["excerpt"], score: row["score"],
                    origin: nil)
            }

        guard req.onlyMasks == true else { return DopeSearchResponse(hits: hits) }

        // 2. Resolve each overlay scope ONCE and keep only hits whose
        // dot-path is overlay-origin. One resolve per scope, never one
        // per hit.
        var provenance = [String: [String: DopeOverlay.Origin]]()
        for scope in scopes where scope.tier?.isOverlay == true {
            guard let baseTier = scope.tier?.masks else { continue }
            let overlayTree = try dope.fetchDopeTree(scope: scope)
            let baseRows: [DopeScopeRow]
            if baseTier.isSessionOwned, let sessionUuid = scope.sessionUuid {
                baseRows = try dope.dopeScopeCandidates(
                    sessionUuid: sessionUuid, scopeType: baseTier, code: scope.code)
            } else {
                baseRows = try DopeScopeRecord.fetchAll(db, sql: """
                    SELECT * FROM dope_scope
                     WHERE project_uuid = ? AND scope_type = ? AND code = ?
                    """, arguments: [scope.projectUuid, baseTier.rawValue, scope.code])
                    .map { $0.wireRow() }
            }
            let baseTree = try baseRows.first.map { try dope.fetchDopeTree(scope: $0) }
            let merged = DopeOverlay.resolve(base: baseTree, overlay: overlayTree)
            provenance[scope.uuid] = merged.resolutions.mapValues(\.origin)
        }

        hits = hits.compactMap { hit in
            guard let byPath = provenance[hit.scopeUuid],
                  let origin = byPath[hit.path] else { return nil }
            switch origin {
            case .overridden, .added, .tombstoned, .orphanedMask:
                return DopeSearchHit(
                    kind: hit.kind, subjectUuid: hit.subjectUuid, scopeUuid: hit.scopeUuid,
                    scopeCode: hit.scopeCode, scopeType: hit.scopeType, path: hit.path,
                    title: hit.title, excerpt: hit.excerpt, score: hit.score,
                    origin: origin.rawValue)
            case .base:
                return nil
            }
        }
        return DopeSearchResponse(hits: hits)
    }

    /// Which scopes a search scope covers. PROMPT means that prompt's own
    /// overlay plus the session base it reads through; SESSION is the
    /// session's scopes; PROJECT is every scope in the project.
    private func searchScopeRows(req: DopeSearchRequest) throws -> [DopeScopeRow] {
        switch req.scope {
        case .prompt:
            guard let promptUuid = req.promptUuid else {
                throw StoreError.badRequest(detail: "--scope prompt requires --prompt-uuid")
            }
            guard let sessionUuid = try String.fetchOne(
                db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            return try DopeScopeRecord.fetchAll(db, sql: """
                SELECT * FROM dope_scope
                 WHERE (session_uuid = ? AND scope_type = 'SESSION_INSTANCE')
                    OR (prompt_uuid = ? AND scope_type = 'SESSION_INSTANCE_ITEM')
                 ORDER BY code
                """, arguments: [sessionUuid, promptUuid]).map { $0.wireRow() }
        case .session:
            guard let sessionUuid = req.sessionUuid else {
                throw StoreError.badRequest(detail: "--scope session requires --session-uuid")
            }
            guard try Row.fetchOne(db, sql: "SELECT 1 FROM session WHERE uuid = ?",
                                   arguments: [sessionUuid]) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
            return try DopeScopeRecord.fetchAll(db, sql: """
                SELECT * FROM dope_scope WHERE session_uuid = ? ORDER BY code
                """, arguments: [sessionUuid]).map { $0.wireRow() }
        case .project:
            guard let projectUuid = req.projectUuid else {
                throw StoreError.badRequest(detail: "--scope project requires --project-uuid")
            }
            guard try Row.fetchOne(db, sql: "SELECT 1 FROM project WHERE uuid = ?",
                                   arguments: [projectUuid]) != nil else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
            return try DopeScopeRecord.fetchAll(db, sql: """
                SELECT * FROM dope_scope WHERE project_uuid = ? ORDER BY code
                """, arguments: [projectUuid]).map { $0.wireRow() }
        }
    }

    /// One UNION arm per source table. Every arm produces the identical column
    /// list, including the dot-path so --only-masks can match resolver
    /// provenance without a second query.
    private static func searchArm(
        _ source: DopeSearchSource, scopePlaceholders: String
    ) -> String {
        let common = "sc.uuid AS scope_uuid, sc.code AS scope_code, sc.scope_type AS scope_type"
        let bm = "bm25(%@, 10.0, 6.0, 2.0)"
        switch source {
        case .scope:
            return """
                SELECT 'scope' AS kind, sc.uuid AS subject_uuid, \(common),
                       sc.code AS path, sc.name AS title,
                       snippet(dope_scope_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_scope_fts")) * 1.0 AS score
                FROM dope_scope_fts fts
                JOIN dope_scope sc ON sc.id = fts.rowid
                WHERE dope_scope_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        case .persistence:
            return """
                SELECT 'persistence' AS kind, d.uuid AS subject_uuid, \(common),
                       d.code AS path, d.name AS title,
                       snippet(dope_persistence_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_persistence_fts")) * 1.1 AS score
                FROM dope_persistence_fts fts
                JOIN dope_persistence d ON d.id = fts.rowid
                JOIN dope_scope sc ON sc.uuid = d.dope_scope_uuid
                WHERE dope_persistence_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        case .entity:
            return """
                SELECT 'entity' AS kind, e.uuid AS subject_uuid, \(common),
                       d.code || '.' || e.code AS path, e.name AS title,
                       snippet(dope_persistence_entity_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_persistence_entity_fts")) * 1.0 AS score
                FROM dope_persistence_entity_fts fts
                JOIN dope_persistence_entity e ON e.id = fts.rowid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_scope sc ON sc.uuid = d.dope_scope_uuid
                WHERE dope_persistence_entity_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        case .property:
            return """
                SELECT 'property' AS kind, p.uuid AS subject_uuid, \(common),
                       d.code || '.' || e.code || '.' || p.code AS path, p.name AS title,
                       snippet(dope_persistence_entity_property_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_persistence_entity_property_fts")) * 1.2 AS score
                FROM dope_persistence_entity_property_fts fts
                JOIN dope_persistence_entity_property p ON p.id = fts.rowid
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_scope sc ON sc.uuid = d.dope_scope_uuid
                WHERE dope_persistence_entity_property_fts MATCH ?
                  AND sc.uuid IN (\(scopePlaceholders))
                """
        case .enumeration:
            return """
                SELECT 'enum' AS kind, n.uuid AS subject_uuid, \(common),
                       d.code || '.enums.' || n.code AS path, n.name AS title,
                       snippet(dope_persistence_enum_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_persistence_enum_fts")) * 1.1 AS score
                FROM dope_persistence_enum_fts fts
                JOIN dope_persistence_enum n ON n.id = fts.rowid
                JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                JOIN dope_scope sc ON sc.uuid = d.dope_scope_uuid
                WHERE dope_persistence_enum_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        case .option:
            return """
                SELECT 'option' AS kind, o.uuid AS subject_uuid, \(common),
                       d.code || '.enums.' || n.code || '.' || o.code AS path, o.name AS title,
                       snippet(dope_persistence_enum_option_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_persistence_enum_option_fts")) * 1.3 AS score
                FROM dope_persistence_enum_option_fts fts
                JOIN dope_persistence_enum_option o ON o.id = fts.rowid
                JOIN dope_persistence_enum n ON n.uuid = o.dope_persistence_enum_uuid
                JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                JOIN dope_scope sc ON sc.uuid = d.dope_scope_uuid
                WHERE dope_persistence_enum_option_fts MATCH ?
                  AND sc.uuid IN (\(scopePlaceholders))
                """
        case .cog:
            return """
                SELECT 'cog' AS kind, c.uuid AS subject_uuid, \(common),
                       c.code AS path, c.name AS title,
                       snippet(dope_cog_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_cog_fts")) * 1.1 AS score
                FROM dope_cog_fts fts
                JOIN dope_cog c ON c.id = fts.rowid
                JOIN dope_scope sc ON sc.uuid = c.dope_scope_uuid
                WHERE dope_cog_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        case .cogElement:
            return """
                SELECT 'cog_element' AS kind, ce.uuid AS subject_uuid, \(common),
                       c.code || '.' || ce.code AS path, ce.name AS title,
                       snippet(dope_cog_element_fts, -1, '', '', '…', 24) AS excerpt,
                       \(String(format: bm, "dope_cog_element_fts")) * 1.1 AS score
                FROM dope_cog_element_fts fts
                JOIN dope_cog_element ce ON ce.id = fts.rowid
                JOIN dope_cog c ON c.uuid = ce.dope_cog_uuid
                JOIN dope_scope sc ON sc.uuid = c.dope_scope_uuid
                WHERE dope_cog_element_fts MATCH ? AND sc.uuid IN (\(scopePlaceholders))
                """
        }
    }
}
