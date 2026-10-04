import Foundation
import GRDB

/// Digested-content data access (KBITE_DIGEST db phase / KBITE_GET /
/// KBITE_FILE_GET / KBITE_SEARCH / KBITE_KEYWORD_TAG).
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never self-transacts. The digest verb's filesystem
/// phases stay in the Store facade — filesystem work never enters a db transaction.
struct KbiteResourceRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Writes scanned artifacts and their files and keywords in one transaction.
    ///
    /// Performs the digest's single write-transaction body, replacing earlier digests
    /// of the same resources. Content is pre-read by the facade.
    ///
    /// - Parameters:
    ///   - code: The kbite code.
    ///   - found: Scanned artifacts with axis1 (primary/secondary), axis2 (type),
    ///     and chewed path.
    ///   - inlinedContents: File contents indexed by [artifact][file].
    ///   - resourceCount: Incremented by the number of resources written.
    ///   - fileCount: Incremented by the number of files written.
    ///   - attachedKeywords: Union of all keywords attached to any resource.
    /// - Returns: The kbite UUID.
    /// - Throws: Errors from database operations.
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
                arguments: [kbiteUuid, item.artifact.resourceName]
            )
            let resourceUuid = try core.insertBase(
                db,
                table: "kbite_resource",
                extra: [
                    "kbite_uuid": kbiteUuid,
                    "resource_name": item.artifact.resourceName,
                    "resource_summary": item.artifact.body,
                    "resource_type": item.axis2,
                    "resource_trust": item.axis1 == "primary" ? 0 : 100,
                ]
            )
            resourceCount += 1

            var fileUuids: [String] = []
            for (entryIndex, entry) in item.artifact.files.enumerated() {
                let content = inlinedContents[itemIndex][entryIndex]
                let fileUuid = try core.insertBase(
                    db,
                    table: "kbite_resource_file",
                    extra: [
                        "kbite_resource_uuid": resourceUuid,
                        "resource_file_name": entry.name,
                        "resource_file_summary": entry.description,
                        "resource_file_content": content,
                    ]
                )
                fileUuids.append(fileUuid)
                fileCount += 1
            }

            for keyword in item.artifact.keywords {
                let keywordUuid = try ensureKeyword(keyword)
                try attachKeyword(
                    table: "kbite_keyword_junction",
                    ownerColumn: "kbite_uuid",
                    ownerUuid: kbiteUuid,
                    keywordUuid: keywordUuid
                )
                for fileUuid in fileUuids {
                    try attachKeyword(
                        table: "resource_file_keyword_junction",
                        ownerColumn: "file_uuid",
                        ownerUuid: fileUuid,
                        keywordUuid: keywordUuid
                    )
                }
                attachedKeywords.insert(keyword)
            }
        }
        try core.appendEvent(
            db,
            kind: .kbiteDigest,
            subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": code,
                "resources": resourceCount,
                "files": fileCount,
                "keywords": attachedKeywords.count,
            ])
        )
        return kbiteUuid
    }

    /// Fetches a kbite and all its resources, files (without content), and keywords.
    ///
    /// Excludes resource file content from the fetch to reduce memory usage.
    ///
    /// - Parameter req: Request with the kbite code.
    /// - Returns: Kbite with resources, files, and keywords.
    /// - Throws: `StoreError.notFound` if the kbite code does not exist.
    func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        // One request, four statements. The file prefetch projects
        // `resource_file_content IS NOT NULL` rather than selecting the
        // column, keeping ~115 MB out of this read.
        guard let manifest = try KbiteWithResources.request(code: req.code).fetchOne(db) else {
            throw StoreError.notFound(entity: "kbite", key: req.code)
        }
        return KbiteGetResponse(
            kbite: manifest.kbite.dto(),
            resources: manifest.resources.map { $0.dto() },
            keywords: manifest.keywords.map(\.keyword)
        )
    }

    /// Fetches a single resource file with its content by UUID.
    ///
    /// The only read that loads resource file content.
    ///
    /// - Parameter req: Request with the file UUID.
    /// - Returns: The file row with content.
    /// - Throws: `StoreError.notFound` if the file UUID does not exist.
    func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        // The one read that SHOULD load resource_file_content: a single file
        // by uuid. The stub listing above must never widen to this.
        guard let row = try KbiteResourceFileRecord.fetch(db, uuid: req.fileUuid) else {
            throw StoreError.notFound(entity: "kbite_resource_file", key: req.fileUuid)
        }
        return KbiteFileGetResponse(file: row.dto())
    }

    /// Searches kbite resource files with FTS5, ranked by bm25 relevance.
    ///
    /// Searches name, summary, and content (in that order of importance). Results are
    /// optionally scoped to a list of kbite UUIDs. The MATCH pattern is built by GRDB
    /// from the raw query; user text never reaches SQL directly. Matched keywords are
    /// filtered by query tokens.
    ///
    /// - Parameters:
    ///   - req: Request with query text, optional kbite UUIDs, and result limit.
    ///   - pattern: The FTS5 search pattern built from the query.
    /// - Returns: Ranked search hits with file info and matched keywords.
    /// - Throws: Errors from database queries.
    func searchKbites(_ req: KbiteSearchRequest, pattern: FTS5Pattern) throws -> KbiteSearchResponse {
        let limit = min(max(req.limit ?? 50, 1), 500)

        // The field is called matchedKeywords, so make that true. The subquery
        // below is keyed on the file uuid alone and knows nothing of the query,
        // so it returns every keyword the file carries; `limit` bounds hits, not
        // keywords per hit. Filtered HERE rather than in the SQL because that
        // subquery sits in the SELECT list ahead of the `MATCH ?` placeholder,
        // so adding predicates means re-ordering StatementArguments.
        // Split the way FTS5's unicode61 tokenizer does, on anything not
        // alphanumeric, so the comparison is SEGMENT-to-token, not substring.
        let queryTokens = Set(
            req.query
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
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
        return KbiteSearchResponse(
            hits:
                try Row.fetchAll(
                    db,
                    sql: sql,
                    arguments: StatementArguments(arguments)
                )
                .map { row in
                    let joined: String? = row["matched_keywords"]
                    return KbiteSearchHit(
                        kbiteCode: row["kbite_code"],
                        kbiteUuid: row["kbite_uuid"],
                        resourceName: row["resource_name"],
                        fileUuid: row["file_uuid"],
                        fileName: row["file_name"],
                        fileSummary: row["file_summary"],
                        // A keyword matches when ANY of its segments is a query token —
                        // so "container" matches `pre_start_init_container` while "a"
                        // matches nothing.
                        matchedKeywords: (joined?.split(separator: ",").map(String.init) ?? [])
                            .filter { keyword in
                                keyword.lowercased()
                                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                                    .contains { queryTokens.contains(String($0)) }
                            },
                        score: row["score"]
                    )
                }
        )
    }

    /// Attaches or detaches normalized keywords from a kbite or resource file.
    ///
    /// Keywords are normalized before processing. Idempotent; attaching an already-attached
    /// keyword or detaching an absent one has no effect.
    ///
    /// - Parameter req: Request with target UUID, keywords, level (kbite or file), and
    ///   whether to attach or detach.
    /// - Returns: Counts of newly attached and detached keywords.
    /// - Throws: `StoreError.notFound` if the target kbite or resource file does not exist;
    ///   errors from database operations.
    func tagKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        let (table, ownerColumn, ownerTable): (String, String, String)
        switch req.level {
        case .kbite:
            (table, ownerColumn, ownerTable) = ("kbite_keyword_junction", "kbite_uuid", "kbite")
        case .file:
            (table, ownerColumn, ownerTable) =
                ("resource_file_keyword_junction", "file_uuid", "kbite_resource_file")
        }
        guard try Table(ownerTable).filter(Column("uuid") == req.targetUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: ownerTable, key: req.targetUuid)
        }

        var attached = 0
        var detached = 0
        for raw in req.keywords {
            let keyword = ChewedArtifactParser.normalizeKeyword(raw)
            guard !keyword.isEmpty else { continue }
            if req.detach {
                guard let keywordUuid = try keywordUuid(keyword) else { continue }
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE \(ownerColumn) = ? AND keyword_uuid = ?",
                    arguments: [req.targetUuid, keywordUuid]
                )
                detached += db.changesCount
            } else {
                let keywordUuid = try ensureKeyword(keyword)
                if try attachKeyword(
                    table: table,
                    ownerColumn: ownerColumn,
                    ownerUuid: req.targetUuid,
                    keywordUuid: keywordUuid
                ) {
                    attached += 1
                }
            }
        }
        if attached > 0 || detached > 0 {
            try core.appendEvent(
                db,
                kind: .kbiteKeywordTag,
                subjectUuid: req.targetUuid,
                payload: Store.jsonPayload([
                    "level": req.level.rawValue,
                    "attached": attached,
                    "detached": detached,
                ])
            )
        }
        return KbiteKeywordTagResponse(attached: attached, detached: detached)
    }

    // MARK: - Keyword primitives

    /// Returns the UUID of a keyword from the shared vocabulary.
    ///
    /// Returns `nil` if the keyword has never been attached to any resource or file.
    ///
    /// - Parameter keyword: The normalized keyword.
    /// - Returns: The keyword UUID, or `nil` if the keyword does not exist.
    /// - Throws: Errors from database queries.
    func keywordUuid(_ keyword: String) throws -> String? {
        try KeywordRecord
            .filter(KeywordRecord.Columns.keyword == keyword)
            .select(KeywordRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
    }

    /// Returns or creates a keyword in the shared vocabulary.
    ///
    /// Idempotent; fetches an existing keyword or creates one if absent. Mirrors
    /// the behavior of `ensureKbite`.
    ///
    /// - Parameter keyword: The normalized keyword text.
    /// - Returns: The keyword UUID.
    /// - Throws: Errors from database operations.
    func ensureKeyword(_ keyword: String) throws -> String {
        if let existing = try keywordUuid(keyword) {
            return existing
        }
        return try core.insertBase(db, table: "keyword", extra: ["keyword": keyword])
    }

    /// Attaches a keyword to a kbite or resource file, idempotently.
    ///
    /// (Internal, not private — `Store+KbiteArchive`'s import reuses it.) Returns
    /// `true` only if a new junction row was created; returns `false` if the
    /// association already exists.
    ///
    /// - Parameters:
    ///   - table: The junction table name.
    ///   - ownerColumn: The column name holding the owner UUID.
    ///   - ownerUuid: The owner (kbite or file) UUID.
    ///   - keywordUuid: The keyword UUID.
    /// - Returns: `true` if a new row was created, `false` if it already existed.
    /// - Throws: Errors from database operations.
    @discardableResult
    func attachKeyword(
        table: String,
        ownerColumn: String,
        ownerUuid: String,
        keywordUuid: String
    ) throws -> Bool {
        let exists =
            try Table(table)
            .filter(Column(ownerColumn) == ownerUuid && Column("keyword_uuid") == keywordUuid)
            .fetchCount(db) > 0
        guard !exists else { return false }
        try core.insertBase(
            db,
            table: table,
            extra: [
                ownerColumn: ownerUuid,
                "keyword_uuid": keywordUuid,
            ]
        )
        return true
    }
}
