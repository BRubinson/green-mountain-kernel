import Foundation
import GRDB

/// Data access for prompt_artifact pointers. Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct ArtifactRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func add(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // UNIQUE(prompt_uuid, file_path): re-registering the same file
        // updates its note instead of failing.
        if let existing = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM prompt_artifact WHERE prompt_uuid = ? AND file_path = ?",
            arguments: [req.promptUuid, req.filePath]
        ) {
            try db.execute(
                sql: """
                    UPDATE prompt_artifact
                    SET note = ?, version = version + 1, updated_at = ?
                    WHERE uuid = ?
                    """,
                arguments: [req.note, Store.isoNow(), existing])
            try core.appendEvent(
                db, kind: .addArtifact, subjectUuid: existing,
                payload: Store.jsonPayload(["file_path": req.filePath]))
            guard let row = try fetchRow(uuid: existing) else {
                throw StoreError.notFound(entity: "prompt_artifact", key: existing)
            }
            return row
        }
        let uuid = try core.insertBase(db, table: "prompt_artifact", extra: [
            "prompt_uuid": req.promptUuid,
            "file_path": req.filePath,
            "note": req.note,
        ])
        try core.appendEvent(
            db, kind: .addArtifact, subjectUuid: uuid,
            payload: Store.jsonPayload(["file_path": req.filePath]))
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "prompt_artifact", key: uuid)
        }
        return row
    }

    func fetchRow(uuid: String) throws -> ArtifactRow? {
        try PromptArtifactRecord.fetch(db, uuid: uuid)?.wireRow()
    }

    func fetchRows(promptUuid: String) throws -> [ArtifactRow] {
        // ORDER BY ... , id is unchanged: `id` is still a column, it is just
        // no longer a Record property.
        try PromptArtifactRecord.fetchAll(
            db,
            where: "prompt_uuid = ?", arguments: [promptUuid],
            orderBy: "created_at, id"
        ).map { $0.wireRow() }
    }
}
