import Foundation
import GRDB

/// PROMPT_DIAGRAM_QUALIFY / _GET / _LIST data access — a prompt's standing
/// reading of a rendered diagram (m0022). Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct PromptDiagramRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func qualify(
        _ req: PromptDiagramQualifyRequest, qualification: String
    ) throws -> PromptQualifiedDiagramRow {
        try requireQualificationTargets(
            promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)

        let extra: [String: (any DatabaseValueConvertible)?] = [
            "prompt_uuid": req.promptUuid,
            "diagram_uuid": req.diagramUuid,
            "rendered_path": req.renderedPath,
            "rendered_revision": req.renderedRevision,
            "render_fingerprint": req.renderFingerprint,
            "qualification": qualification,
        ]
        let uuid: String
        // UNIQUE(prompt_uuid, diagram_uuid): re-qualifying REPLACES the
        // reading in place, keeping the row uuid stable so anything
        // pointing at it still points at it.
        if let existing = try String.fetchOne(
            db,
            sql: """
                SELECT uuid FROM prompt_qualified_diagram
                WHERE prompt_uuid = ? AND diagram_uuid = ?
                """,
            arguments: [req.promptUuid, req.diagramUuid]
        ) {
            try db.execute(
                sql: """
                    UPDATE prompt_qualified_diagram
                    SET rendered_path = ?, rendered_revision = ?,
                        render_fingerprint = ?, qualification = ?,
                        version = version + 1, updated_at = ?
                    WHERE uuid = ?
                    """,
                arguments: [req.renderedPath, req.renderedRevision,
                            req.renderFingerprint, qualification,
                            Store.isoNow(), existing])
            uuid = existing
        } else {
            uuid = try core.insertBase(
                db, table: "prompt_qualified_diagram", extra: extra)
        }

        try core.appendEvent(
            db, kind: .promptDiagramQualified, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "prompt_uuid": req.promptUuid,
                "diagram_uuid": req.diagramUuid,
            ]))

        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "prompt_qualified_diagram", key: uuid)
        }
        return row
    }

    func get(_ req: PromptDiagramGetRequest) throws -> PromptQualifiedDiagramRow {
        try requireQualificationTargets(
            promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)

        let rows = try fetchRows(promptUuid: req.promptUuid, diagramUuid: req.diagramUuid)
        guard let first = rows.first else {
            // The prompt is real and nothing is recorded against it — the
            // caller's next move is to render, read and qualify, not to
            // doubt the uuid. Same discrimination the summary families make.
            throw StoreError.summaryAbsent(
                entity: "prompt_qualified_diagram", promptUuid: req.promptUuid)
        }
        guard rows.count == 1 else {
            throw StoreError.badRequest(
                detail: "prompt has \(rows.count) qualified diagrams — "
                      + "name one with a diagram uuid, or list them")
        }
        return first
    }

    func list(_ req: PromptDiagramListRequest) throws -> PromptDiagramListResponse {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // Empty is a normal answer here (the prompt has attached no
        // diagrams yet), so list never raises where get would.
        return PromptDiagramListResponse(
            qualifications: try fetchRows(promptUuid: req.promptUuid, diagramUuid: nil))
    }

    // MARK: - Shared helpers

    /// Existence first, in the same transaction as the write. Without it an
    /// unknown uuid surfaces as a raw FK failure, which tells the caller
    /// nothing about WHICH end was wrong.
    private func requireQualificationTargets(
        promptUuid: String, diagramUuid: String?
    ) throws {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        guard let diagramUuid else { return }
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM diagram WHERE uuid = ?", arguments: [diagramUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "diagram", key: diagramUuid)
        }
    }

    func fetchRow(uuid: String) throws -> PromptQualifiedDiagramRow? {
        try PromptQualifiedDiagramRecord.fetchOne(
            db,
            sql: "\(Self.qualifiedDiagramSelect) WHERE uuid = ?",
            arguments: [uuid]
        )?.wireRow()
    }

    func fetchRows(
        promptUuid: String, diagramUuid: String?
    ) throws -> [PromptQualifiedDiagramRow] {
        var sql = "\(Self.qualifiedDiagramSelect) WHERE prompt_uuid = ?"
        var arguments: [any DatabaseValueConvertible] = [promptUuid]
        if let diagramUuid {
            sql += " AND diagram_uuid = ?"
            arguments.append(diagramUuid)
        }
        sql += " ORDER BY created_at, id"
        return try PromptQualifiedDiagramRecord
            .fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { $0.wireRow() }
    }

    private static let qualifiedDiagramSelect = """
        SELECT uuid, prompt_uuid, diagram_uuid, rendered_path, rendered_revision,
               render_fingerprint, qualification, version, created_at, updated_at, id
        FROM prompt_qualified_diagram
        """
}
