import Foundation
import GRDB

/// Portable-kbite db phases (KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE).
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. The file I/O phases stay on the Store facade — filesystem
/// work never enters a db transaction.
struct KbiteArchiveRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Assemble the scrubbed export document (read-only — no event).
    func exportDocument(
        code: String, anonymize: [KbitePrefixRule]
    ) throws -> (document: KbiteExportDocument, fileKeywordCount: Int) {
        guard let kbiteRow = try Row.fetchOne(
            db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [code]
        ) else {
            throw StoreError.notFound(entity: "kbite", key: code)
        }
        let kbiteUuid: String = kbiteRow["uuid"]

        let kbiteKeywords = try String.fetchAll(db, sql: """
            SELECT kw.keyword FROM keyword kw
            JOIN kbite_keyword_junction j ON j.keyword_uuid = kw.uuid
            WHERE j.kbite_uuid = ? ORDER BY kw.keyword
            """, arguments: [kbiteUuid])

        var fileKeywordCount = 0
        var resources: [KbiteExportDocument.Resource] = []
        for resourceRow in try Row.fetchAll(db, sql: """
            SELECT uuid, resource_name, resource_summary, resource_type, resource_trust
            FROM kbite_resource WHERE kbite_uuid = ? ORDER BY resource_name
            """, arguments: [kbiteUuid]) {
            let resourceUuid: String = resourceRow["uuid"]
            var files: [KbiteExportDocument.File] = []
            for fileRow in try Row.fetchAll(db, sql: """
                SELECT uuid, resource_file_name, resource_file_summary, resource_file_content
                FROM kbite_resource_file WHERE kbite_resource_uuid = ?
                ORDER BY resource_file_name
                """, arguments: [resourceUuid]) {
                let fileUuid: String = fileRow["uuid"]
                let keywords = try String.fetchAll(db, sql: """
                    SELECT kw.keyword FROM keyword kw
                    JOIN resource_file_keyword_junction j ON j.keyword_uuid = kw.uuid
                    WHERE j.file_uuid = ? ORDER BY kw.keyword
                    """, arguments: [fileUuid])
                fileKeywordCount += keywords.count
                let content: String? = fileRow["resource_file_content"]
                files.append(KbiteExportDocument.File(
                    resourceFileName: fileRow["resource_file_name"],
                    resourceFileSummary: KbiteArchive.scrub(
                        fileRow["resource_file_summary"], rules: anonymize),
                    resourceFileContent: content.map {
                        KbiteArchive.scrub($0, rules: anonymize)
                    },
                    keywords: keywords
                ))
            }
            resources.append(KbiteExportDocument.Resource(
                resourceName: resourceRow["resource_name"],
                resourceSummary: KbiteArchive.scrub(
                    resourceRow["resource_summary"], rules: anonymize),
                resourceType: resourceRow["resource_type"],
                resourceTrust: resourceRow["resource_trust"],
                files: files
            ))
        }
        let document = KbiteExportDocument(
            code: code,
            exportedAt: Store.isoNow(),
            sourceKbiteUuid: kbiteUuid,
            kbiteKeywords: kbiteKeywords,
            resources: resources
        )
        return (document, fileKeywordCount)
    }

    /// One-transaction import apply — the pre-decoded, pre-validated,
    /// rehydrated document in; rows out. Collision `skip` leaves the existing
    /// kbite untouched; `overwrite` replaces content under the EXISTING kbite
    /// uuid (ensureKbite — never delete+reinsert the kbite row, whose CASCADE
    /// would silently drop every scope registration). Resource/file uuids are
    /// re-minted; keywords remap by TEXT through the shared vocabulary.
    /// Never touches registration tables.
    func importApply(
        rehydrated: KbiteExportDocument, onCollision: KbiteImportCollision
    ) throws -> KbiteImportResponse {
        let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [rehydrated.code])
        if let existing, onCollision == .skip {
            return KbiteImportResponse(
                kbiteUuid: existing, code: rehydrated.code,
                imported: false, skippedExisting: true,
                resourceCount: 0, fileCount: 0, keywordCount: 0)
        }

        let kbites = KbiteResourceRepository(db: db, core: core)
        let kbiteUuid = try ContextRepository(db: db, core: core).ensureKbite(code: rehydrated.code)
        // Clean-slate content replace under the stable kbite uuid:
        // resources cascade to files + file junctions; the kbite-level
        // keyword junction is cleared explicitly. Registrations survive.
        try db.execute(
            sql: "DELETE FROM kbite_resource WHERE kbite_uuid = ?", arguments: [kbiteUuid])
        try db.execute(
            sql: "DELETE FROM kbite_keyword_junction WHERE kbite_uuid = ?", arguments: [kbiteUuid])

        var fileCount = 0
        var attachedKeywords: Set<String> = []
        for resource in rehydrated.resources {
            let resourceUuid = try core.insertBase(db, table: "kbite_resource", extra: [
                "kbite_uuid": kbiteUuid,
                "resource_name": resource.resourceName,
                "resource_summary": resource.resourceSummary,
                "resource_type": resource.resourceType,
                "resource_trust": resource.resourceTrust,
            ])
            for file in resource.files {
                let fileUuid = try core.insertBase(db, table: "kbite_resource_file", extra: [
                    "kbite_resource_uuid": resourceUuid,
                    "resource_file_name": file.resourceFileName,
                    "resource_file_summary": file.resourceFileSummary,
                    "resource_file_content": file.resourceFileContent,
                ])
                fileCount += 1
                for keyword in file.keywords {
                    let keywordUuid = try kbites.ensureKeyword(keyword)
                    try kbites.attachKeyword(
                        table: "resource_file_keyword_junction",
                        ownerColumn: "file_uuid", ownerUuid: fileUuid, keywordUuid: keywordUuid)
                    attachedKeywords.insert(keyword)
                }
            }
        }
        for keyword in rehydrated.kbiteKeywords {
            let keywordUuid = try kbites.ensureKeyword(keyword)
            try kbites.attachKeyword(
                table: "kbite_keyword_junction",
                ownerColumn: "kbite_uuid", ownerUuid: kbiteUuid, keywordUuid: keywordUuid)
            attachedKeywords.insert(keyword)
        }

        // An overwrite is exactly the import/delete cycle the GC exists
        // for — the previous content's keywords must not orphan forever.
        let gcCount = existing != nil ? try gcOrphanKeywords() : 0

        try core.appendEvent(
            db, kind: .kbiteImport, subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": rehydrated.code,
                "overwrote_existing": existing != nil,
                "resources": rehydrated.resources.count,
                "files": fileCount,
                "keywords": attachedKeywords.count,
                "gc_keywords": gcCount,
            ]))
        return KbiteImportResponse(
            kbiteUuid: kbiteUuid, code: rehydrated.code,
            imported: true, skippedExisting: false,
            resourceCount: rehydrated.resources.count,
            fileCount: fileCount,
            keywordCount: attachedKeywords.count)
    }

    /// One cascading delete plus shared-vocabulary GC. Registrations going
    /// with the row is the DESIRED behavior here; daemon_event history rows
    /// survive (subject_uuid is not FK'd — append-only ethos holds).
    func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        guard let kbiteUuid = try String.fetchOne(
            db, sql: "SELECT uuid FROM kbite WHERE code = ?", arguments: [req.code]
        ) else {
            throw StoreError.notFound(entity: "kbite", key: req.code)
        }
        let resources = try Int.fetchOne(db, sql:
            "SELECT COUNT(*) FROM kbite_resource WHERE kbite_uuid = ?",
            arguments: [kbiteUuid]) ?? 0
        let files = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM kbite_resource_file f
            JOIN kbite_resource r ON r.uuid = f.kbite_resource_uuid
            WHERE r.kbite_uuid = ?
            """, arguments: [kbiteUuid]) ?? 0
        var registrations = 0
        for scope in KbiteScope.allCases {
            registrations += try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM \(scope.rawValue)_active_kbite WHERE kbite_uuid = ?",
                arguments: [kbiteUuid]) ?? 0
        }

        // CASCADE clears resources/files/junctions/registrations; the
        // FTS AD triggers keep the mirror consistent (recursive ON).
        try db.execute(sql: "DELETE FROM kbite WHERE uuid = ?", arguments: [kbiteUuid])

        let gcCount = try gcOrphanKeywords()

        try core.appendEvent(
            db, kind: .kbiteDelete, subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": req.code,
                "resources": resources,
                "files": files,
                "registrations": registrations,
                "gc_keywords": gcCount,
            ]))
        return KbiteDeleteResponse(
            kbiteUuid: kbiteUuid, code: req.code,
            deletedResources: resources, deletedFiles: files,
            deletedRegistrations: registrations, gcKeywordCount: gcCount)
    }

    /// GC keywords no junction references any more (delete AND overwrite
    /// import would otherwise bloat the shared vocabulary forever). Safe as
    /// a global sweep: only the two kbite junctions reference keyword.
    func gcOrphanKeywords() throws -> Int {
        try db.execute(sql: """
            DELETE FROM keyword WHERE uuid NOT IN (
                SELECT keyword_uuid FROM kbite_keyword_junction
                UNION SELECT keyword_uuid FROM resource_file_keyword_junction
            )
            """)
        return db.changesCount
    }
}
