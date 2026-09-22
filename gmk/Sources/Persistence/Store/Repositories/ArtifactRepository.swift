import Foundation
import GRDB

/// Data access for prompt_artifact pointers. Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct ArtifactRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func add(_ req: ArtifactAddRequest) throws -> ArtifactRow {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // UNIQUE(prompt_uuid, file_path): re-registering the same file
        // updates its note instead of failing.
        if let existing =
            try PromptArtifactRecord
            .filter(PromptArtifactRecord.Columns.promptUuid == req.promptUuid)
            .filter(PromptArtifactRecord.Columns.filePath == req.filePath)
            .select(PromptArtifactRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            try db.execute(
                sql: """
                    UPDATE prompt_artifact
                    SET note = ?, version = version + 1, updated_at = ?
                    WHERE uuid = ?
                    """,
                arguments: [req.note, Store.isoNow(), existing]
            )
            try core.appendEvent(
                db,
                kind: .addArtifact,
                subjectUuid: existing,
                payload: Store.jsonPayload(["file_path": req.filePath])
            )
            guard let row = try fetchRow(uuid: existing) else {
                throw StoreError.notFound(entity: "prompt_artifact", key: existing)
            }
            return row
        }
        let uuid = try core.insertBase(
            db,
            table: "prompt_artifact",
            extra: [
                "prompt_uuid": req.promptUuid,
                "file_path": req.filePath,
                "note": req.note,
            ]
        )
        try core.appendEvent(
            db,
            kind: .addArtifact,
            subjectUuid: uuid,
            payload: Store.jsonPayload(["file_path": req.filePath])
        )
        guard let row = try fetchRow(uuid: uuid) else {
            throw StoreError.notFound(entity: "prompt_artifact", key: uuid)
        }
        return row
    }

    func fetchRow(uuid: String) throws -> ArtifactRow? {
        try PromptArtifactRecord.fetch(db, uuid: uuid)?.dto()
    }

    func fetchRows(promptUuid: String) throws -> [ArtifactRow] {
        // `id` orders the tie-break: it is a column even though no Record
        // exposes it as a property.
        try PromptArtifactRecord
            .filter(PromptArtifactRecord.Columns.promptUuid == promptUuid)
            .order(PromptArtifactRecord.Columns.createdAt, Column("id"))
            .fetchAll(db)
            .map { $0.dto() }
    }
}
