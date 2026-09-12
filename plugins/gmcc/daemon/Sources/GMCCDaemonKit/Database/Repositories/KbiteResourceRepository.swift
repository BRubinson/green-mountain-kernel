import Foundation
import GRDB

/// Digested-content data access (KBITE_DIGEST db phase / KBITE_GET /
/// KBITE_FILE_GET / KBITE_SEARCH / KBITE_KEYWORD_TAG). Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
/// The digest verb's filesystem phases stay in the Store facade — filesystem
/// work never enters a db transaction.
struct KbiteResourceRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// The digest's single write-transaction body: resource/file/keyword rows
    /// from the pre-scanned artifacts (content pre-read by the facade).
    func digestApply(
        code: String,
        found: [(artifact: ChewedArtifact, axis1: String, axis2: String, chewedPath: String)],
        inlinedContents: [[String?]],
        resourceCount: inout Int,
        fileCount: inout Int,
        attachedKeywords: inout Set<String>
    ) throws -> String {
        let kbiteUuid = try ContextRepository(db: db, core: core).ensureKbite(code: code)
        for (itemIndex, item) in found.enumerated() {
            // Replace an earlier digest of the same resource: the CASCADE
            // clears its files/junctions and the FTS triggers keep the
            // mirror in sync (recursive_triggers is ON).
            try db.execute(
                sql: "DELETE FROM kbite_resource WHERE kbite_uuid = ? AND resource_name = ?",
                arguments: [kbiteUuid, item.artifact.resourceName])
            let resourceUuid = try core.insertBase(db, table: "kbite_resource", extra: [
                "kbite_uuid": kbiteUuid,
                "resource_name": item.artifact.resourceName,
                "resource_summary": item.artifact.body,
                "resource_type": item.axis2,
                "resource_trust": item.axis1 == "primary" ? 0 : 100,
            ])
            resourceCount += 1

            var fileUuids: [String] = []
            for (entryIndex, entry) in item.artifact.files.enumerated() {
                let content = inlinedContents[itemIndex][entryIndex]
                let fileUuid = try core.insertBase(db, table: "kbite_resource_file", extra: [
                    "kbite_resource_uuid": resourceUuid,
                    "resource_file_name": entry.name,
                    "resource_file_summary": entry.description,
                    "resource_file_content": content,
                ])
                fileUuids.append(fileUuid)
                fileCount += 1
            }

            for keyword in item.artifact.keywords {
                let keywordUuid = try ensureKeyword(keyword)
                try attachKeyword(
                    table: "kbite_keyword_junction",
                    ownerColumn: "kbite_uuid", ownerUuid: kbiteUuid, keywordUuid: keywordUuid)
                for fileUuid in fileUuids {
                    try attachKeyword(
                        table: "resource_file_keyword_junction",
                        ownerColumn: "file_uuid", ownerUuid: fileUuid, keywordUuid: keywordUuid)
                }
                attachedKeywords.insert(keyword)
            }
        }
        try core.appendEvent(
            db, kind: .kbiteDigest, subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": code,
                "resources": resourceCount,
                "files": fileCount,
                "keywords": attachedKeywords.count,
            ]))
        return kbiteUuid
    }

    func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        guard let kbiteRecord = try KbiteRecord.fetchOne(
            db, where: "code = ?", arguments: [req.code]
        ) else {
            throw StoreError.notFound(entity: "kbite", key: req.code)
        }
        let kbite = kbiteRecord.wireRow()
        var resources: [KbiteResourceRow] = []
        for row in try KbiteResourceRecord.fetchAll(
            db, where: "kbite_uuid = ?", arguments: [kbite.uuid],
            orderBy: "resource_name"
        ) {
            // DELIBERATELY not a SELECT * over kbite_resource_file: the
            // computed has_content keeps ~115 MB of resource_file_content out
            // of this read. See KbiteResourceFileStubRecord.
            let stubs = try KbiteResourceFileStubRecord.fetchAll(db, sql: """
                SELECT uuid, resource_file_name, resource_file_summary,
                       resource_file_content IS NOT NULL AS has_content
                FROM kbite_resource_file WHERE kbite_resource_uuid = ?
                ORDER BY resource_file_name
                """, arguments: [row.uuid]).map { $0.wireStub() }
            resources.append(row.wireRow(files: stubs))
        }
        let keywords = try String.fetchAll(db, sql: """
            SELECT kw.keyword FROM keyword kw
            JOIN kbite_keyword_junction j ON j.keyword_uuid = kw.uuid
            WHERE j.kbite_uuid = ? ORDER BY kw.keyword
            """, arguments: [kbite.uuid])
        return KbiteGetResponse(kbite: kbite, resources: resources, keywords: keywords)
    }

    /// The targeted load replacing "cat the chewed file".
    func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        // The one read that SHOULD load resource_file_content: a single file
        // by uuid. The stub listing above must never widen to this.
        guard let row = try KbiteResourceFileRecord.fetch(db, uuid: req.fileUuid) else {
            throw StoreError.notFound(entity: "kbite_resource_file", key: req.fileUuid)
        }
        return KbiteFileGetResponse(file: row.wireRow())
    }

    /// FTS5 query, bm25-ranked (name ≫ summary ≫ content, smaller = better),
    /// optionally scoped to a kbite_uuids list. The MATCH pattern is built by
    /// GRDB from the raw query — user text never reaches SQL.
    func searchKbites(_ req: KbiteSearchRequest, pattern: FTS5Pattern) throws -> KbiteSearchResponse {
        let limit = min(max(req.limit ?? 50, 1), 500)
        var sql = """
            SELECT k.code AS kbite_code, kr.kbite_uuid AS kbite_uuid,
                   kr.resource_name AS resource_name,
                   f.uuid AS file_uuid, f.resource_file_name AS file_name,
                   f.resource_file_summary AS file_summary,
                   bm25(kbite_resource_file_fts, 10.0, 5.0, 1.0) AS score,
                   (SELECT group_concat(kw.keyword, ',')
                      FROM resource_file_keyword_junction j
                      JOIN keyword kw ON kw.uuid = j.keyword_uuid
                     WHERE j.file_uuid = f.uuid) AS matched_keywords
            FROM kbite_resource_file_fts fts
            JOIN kbite_resource_file f ON f.id = fts.rowid
            JOIN kbite_resource kr ON kr.uuid = f.kbite_resource_uuid
            JOIN kbite k ON k.uuid = kr.kbite_uuid
            WHERE kbite_resource_file_fts MATCH ?
            """
        var arguments: [any DatabaseValueConvertible] = [pattern]
        if let kbiteUuids = req.kbiteUuids, !kbiteUuids.isEmpty {
            let placeholders = Array(repeating: "?", count: kbiteUuids.count).joined(separator: ", ")
            sql += " AND kr.kbite_uuid IN (\(placeholders))"
            arguments.append(contentsOf: kbiteUuids)
        }
        sql += " ORDER BY score LIMIT \(limit)"
        return KbiteSearchResponse(hits: try Row.fetchAll(
            db, sql: sql, arguments: StatementArguments(arguments)
        ).map { row in
            let joined: String? = row["matched_keywords"]
            return KbiteSearchHit(
                kbiteCode: row["kbite_code"],
                kbiteUuid: row["kbite_uuid"],
                resourceName: row["resource_name"],
                fileUuid: row["file_uuid"],
                fileName: row["file_name"],
                fileSummary: row["file_summary"],
                matchedKeywords: joined?.split(separator: ",").map(String.init) ?? [],
                score: row["score"]
            )
        })
    }

    /// Attach/detach normalized keywords at kbite or resource-file level.
    func tagKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        let (table, ownerColumn, ownerTable): (String, String, String)
        switch req.level {
        case .kbite:
            (table, ownerColumn, ownerTable) = ("kbite_keyword_junction", "kbite_uuid", "kbite")
        case .file:
            (table, ownerColumn, ownerTable) =
                ("resource_file_keyword_junction", "file_uuid", "kbite_resource_file")
        }
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM \(ownerTable) WHERE uuid = ?", arguments: [req.targetUuid]
        ) != nil else {
            throw StoreError.notFound(entity: ownerTable, key: req.targetUuid)
        }

        var attached = 0
        var detached = 0
        for raw in req.keywords {
            let keyword = ChewedArtifactParser.normalizeKeyword(raw)
            guard !keyword.isEmpty else { continue }
            if req.detach {
                guard let keywordUuid = try String.fetchOne(
                    db, sql: "SELECT uuid FROM keyword WHERE keyword = ?", arguments: [keyword]
                ) else { continue }
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE \(ownerColumn) = ? AND keyword_uuid = ?",
                    arguments: [req.targetUuid, keywordUuid])
                detached += db.changesCount
            } else {
                let keywordUuid = try ensureKeyword(keyword)
                if try attachKeyword(
                    table: table, ownerColumn: ownerColumn,
                    ownerUuid: req.targetUuid, keywordUuid: keywordUuid) {
                    attached += 1
                }
            }
        }
        if attached > 0 || detached > 0 {
            try core.appendEvent(
                db, kind: .kbiteKeywordTag, subjectUuid: req.targetUuid,
                payload: Store.jsonPayload([
                    "level": req.level.rawValue,
                    "attached": attached,
                    "detached": detached,
                ]))
        }
        return KbiteKeywordTagResponse(attached: attached, detached: detached)
    }

    // MARK: - Keyword primitives

    /// Upsert the shared vocabulary by normalized text (mirrors ensureKbite).
    func ensureKeyword(_ keyword: String) throws -> String {
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM keyword WHERE keyword = ?", arguments: [keyword]
        ) {
            return existing
        }
        return try core.insertBase(db, table: "keyword", extra: ["keyword": keyword])
    }

    /// Idempotent junction insert; returns whether a row was created.
    /// (Internal, not private — Store+KbiteArchive's import reuses it.)
    @discardableResult
    func attachKeyword(
        table: String, ownerColumn: String, ownerUuid: String, keywordUuid: String
    ) throws -> Bool {
        let exists = try Row.fetchOne(
            db,
            sql: "SELECT 1 FROM \(table) WHERE \(ownerColumn) = ? AND keyword_uuid = ?",
            arguments: [ownerUuid, keywordUuid]) != nil
        guard !exists else { return false }
        try core.insertBase(db, table: table, extra: [
            ownerColumn: ownerUuid,
            "keyword_uuid": keywordUuid,
        ])
        return true
    }
}
