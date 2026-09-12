import Foundation
import GRDB

/// Diagram Studio (v23) data access: cross-tier search/browse and the row
/// delete. Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts.
struct DiagramStudioRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func diagramSearch(_ req: DiagramSearchRequest, pattern: FTS5Pattern?) throws -> DiagramSearchResponse {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM project WHERE uuid = ?",
            arguments: [req.projectUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "project", key: req.projectUuid)
        }
        if let sessionUuid = req.sessionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: sessionUuid)
            }
        }
        let limit = min(max(req.limit ?? 50, 1), 500)
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

        let rows: [Row]
        if let pattern {
            // bm25 is negative-better; ORDER BY score ascending is rank
            // order (the Store+Search convention).
            rows = try Row.fetchAll(db, sql: """
                SELECT d.*, s.instance_uuid AS instance_uuid
                  FROM diagram_fts f
                  JOIN diagram d ON d.id = f.rowid
                  LEFT JOIN session s ON s.uuid = d.session_uuid
                 WHERE diagram_fts MATCH ?
                   AND \(conditions.joined(separator: " AND "))
                 ORDER BY bm25(diagram_fts, 6.0, 4.0, 1.0)
                 LIMIT \(limit)
                """, arguments: StatementArguments([pattern] + args))
        } else {
            rows = try Row.fetchAll(db, sql: """
                \(DiagramRepository.diagramSelect)
                 WHERE \(conditions.joined(separator: " AND "))
                 ORDER BY d.updated_at DESC, d.code
                 LIMIT \(limit)
                """, arguments: StatementArguments(args))
        }
        return DiagramSearchResponse(diagrams: try rows.map(DiagramRepository.diagramRow))
    }

    func diagramDelete(_ req: DiagramDeleteRequest) throws -> DiagramDeleteResponse {
        guard let diagram = try diagram.fetchDiagram(uuid: req.diagramUuid) else {
            throw StoreError.notFound(entity: "diagram", key: req.diagramUuid)
        }
        if let expected = req.expectedRevision, expected != diagram.revision {
            throw StoreError.revisionConflict(
                scopeUuid: diagram.uuid, expected: expected, actual: diagram.revision)
        }
        let elements = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM diagram_element WHERE diagram_uuid = ?",
            arguments: [diagram.uuid]) ?? 0
        let storagePath = try self.diagram.diagramOwnerStoragePath(diagram: diagram)
        // The durable goodbye rides BEFORE the row drop, carrying the
        // final revision — live galleries/editors drop the card on it.
        try self.diagram.recordDiagramChange(
            diagram: diagram, action: "deleted", elementUuid: nil,
            mutationCount: nil, revision: diagram.revision)
        // One statement: elements + subtypes + vertices cascade via FKs,
        // the FTS row via its delete trigger, and m0022's qualified
        // readings via their own CASCADE.
        try db.execute(sql: "DELETE FROM diagram WHERE uuid = ?",
                       arguments: [diagram.uuid])
        return DiagramDeleteResponse(
            deletedUuid: diagram.uuid, code: diagram.code,
            cascadedElements: elements, ownerStoragePath: storagePath,
            gmccDiagramPath: diagram.gmccDiagramPath)
    }
}
