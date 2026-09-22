import Foundation
import GRDB

/// Diagram Studio (v23) data access: cross-tier search/browse and the row
/// delete. Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts.
struct DiagramStudioRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func diagramSearch(_ req: DiagramSearchRequest, pattern: FTS5Pattern?) throws -> DiagramSearchResponse {
        guard try ProjectRecord.all().withUuid(req.projectUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: "project", key: req.projectUuid)
        }
        if let sessionUuid = req.sessionUuid {
            try diagram.requireSession(uuid: sessionUuid)
        }
        let limit = min(max(req.limit ?? 50, 1), 500)

        let rows: [DiagramWithOwner]
        if let pattern {
            rows = try rankedSearch(req, pattern: pattern, limit: limit)
        } else {
            var request = DiagramWithOwner.request()
                .filter(DiagramRecord.Columns.projectUuid == req.projectUuid)
            if let sessionUuid = req.sessionUuid {
                request = request.filter(DiagramRecord.Columns.sessionUuid == sessionUuid)
            }
            if let visibility = req.visibility {
                request = request.filter(DiagramRecord.Columns.visibility == visibility)
            }
            rows =
                try request
                .order(DiagramRecord.Columns.updatedAt.desc, DiagramRecord.Columns.code)
                .limit(limit)
                .fetchAll(db)
        }
        return DiagramSearchResponse(diagrams: rows.map { $0.dto() })
    }

    /// bm25 is negative-better; ORDER BY score ascending is rank order (the
    /// Store+Search convention). The scoring function is callable only on a
    /// query over the fts table, so this branch spells its own join.
    private func rankedSearch(
        _ req: DiagramSearchRequest,
        pattern: FTS5Pattern,
        limit: Int
    ) throws -> [DiagramWithOwner] {
        var conditions = ["d.project_uuid = ?"]
        var args: [any DatabaseValueConvertible] = [req.projectUuid]
        if let sessionUuid = req.sessionUuid {
            conditions.append("d.session_uuid = ?")
            args.append(sessionUuid)
        }
        if let visibility = req.visibility {
            conditions.append("d.visibility = ?")
            args.append(visibility)
        }
        return try DiagramWithOwner.fetchAll(
            db,
            sql: """
                SELECT d.*, s.instance_uuid AS instanceUuid
                  FROM diagram_fts f
                  JOIN diagram d ON d.id = f.rowid
                  LEFT JOIN session s ON s.uuid = d.session_uuid
                 WHERE diagram_fts MATCH ?
                   AND \(conditions.joined(separator: " AND "))
                 ORDER BY bm25(diagram_fts, 6.0, 4.0, 1.0)
                 LIMIT \(limit)
                """,
            arguments: StatementArguments([pattern] + args)
        )
    }

    func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        guard let diagram = try diagram.fetchDiagram(uuid: req.diagramUuid) else {
            throw StoreError.notFound(entity: "diagram", key: req.diagramUuid)
        }
        if let expected = req.expectedRevision, expected != diagram.revision {
            throw StoreError.revisionConflict(
                scopeUuid: diagram.uuid,
                expected: expected,
                actual: diagram.revision
            )
        }
        let elements =
            try DiagramElementRecord
            .filter(DiagramElementRecord.Columns.diagramUuid == diagram.uuid)
            .fetchCount(db)
        let storagePath = try self.diagram.diagramOwnerStoragePath(diagram: diagram)
        // The durable goodbye rides BEFORE the row drop, carrying the
        // final revision — live galleries/editors drop the card on it.
        try self.diagram.recordDiagramChange(
            diagram: diagram,
            action: "deleted",
            elementUuid: nil,
            mutationCount: nil,
            revision: diagram.revision
        )
        // One statement: elements + subtypes + vertices cascade via FKs,
        // the FTS row via its delete trigger, and m0022's qualified
        // readings via their own CASCADE.
        try db.execute(
            sql: "DELETE FROM diagram WHERE uuid = ?",
            arguments: [diagram.uuid]
        )
        return DiagramDeleteResponse(
            deletedUuid: diagram.uuid,
            code: diagram.code,
            cascadedElements: elements,
            ownerStoragePath: storagePath,
            gmccDiagramPath: diagram.gmccDiagramPath
        )
    }
}
