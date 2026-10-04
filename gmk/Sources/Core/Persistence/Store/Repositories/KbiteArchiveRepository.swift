import Foundation
import GRDB

/// Portable-kbite db phases (KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE).
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. The file I/O phases stay on the Store facade — filesystem
/// work never enters a db transaction.
struct KbiteArchiveRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Assembles a scrubbed export document for a kbite.
    ///
    /// - Parameters:
    ///   - code: The kbite code to export.
    ///   - anonymize: Prefix rules to scrub sensitive text in the output.
    /// - Returns: Tuple with the export document and total file keyword count.
    /// - Throws: `StoreError.notFound` if the kbite code does not exist.
    func exportDocument(
        code: String,
        anonymize: [KbitePrefixRule]
    ) throws -> (document: KbiteExportDocument, fileKeywordCount: Int) {
        guard let manifest = try KbiteWithResources.request(code: code).fetchOne(db) else {
            throw StoreError.notFound(entity: "kbite", key: code)
        }
        var fileKeywordCount = 0
        var resources: [KbiteExportDocument.Resource] = []
        for resource in manifest.resources {
            var files: [KbiteExportDocument.File] = []
            for head in resource.files {
                let file = try exportFile(head: head, anonymize: anonymize)
                fileKeywordCount += file.keywords.count
                files.append(file)
            }
            resources.append(
                KbiteExportDocument.Resource(
                    resourceName: resource.resource.resourceName,
                    resourceSummary: KbiteArchive.scrub(
                        resource.resource.resourceSummary,
                        rules: anonymize
                    ),
                    resourceType: resource.resource.resourceType,
                    resourceTrust: Int(resource.resource.resourceTrust),
                    files: files
                )
            )
        }
        let document = KbiteExportDocument(
            code: code,
            exportedAt: Store.isoNow(),
            sourceKbiteUuid: manifest.kbite.uuid,
            kbiteKeywords: manifest.keywords.map(\.keyword),
            resources: resources
        )
        return (document, fileKeywordCount)
    }

    /// Assembles one file's export entry with scrubbed content.
    ///
    /// The content column is read here, a single row at a time, not through
    /// the manifest.
    ///
    /// - Parameters:
    ///   - head: The file metadata from the resource.
    ///   - anonymize: Prefix rules to scrub sensitive text.
    /// - Returns: The export file entry with scrubbed content and keywords.
    /// - Throws: Any database error while fetching keywords or content.
    private func exportFile(
        head: KbiteResourceFileHead,
        anonymize: [KbitePrefixRule]
    ) throws -> KbiteExportDocument.File {
        let keywords = try KbiteRequests.fileKeywords(fileUuid: head.uuid).fetchAll(db)
        let content = try KbiteResourceFileRecord.fetch(db, uuid: head.uuid)?.resourceFileContent
        return KbiteExportDocument.File(
            resourceFileName: head.resourceFileName,
            resourceFileSummary: KbiteArchive.scrub(head.resourceFileSummary, rules: anonymize),
            resourceFileContent: content.map { KbiteArchive.scrub($0, rules: anonymize) },
            keywords: keywords
        )
    }

    /// Applies a validated import document to the database in one transaction.
    ///
    /// Collision `skip` leaves the existing kbite untouched; `overwrite`
    /// replaces content under the existing kbite UUID. Resource and file UUIDs
    /// are re-minted; keywords remap by text through the shared vocabulary.
    /// Registration tables are never touched.
    ///
    /// - Parameters:
    ///   - rehydrated: The pre-decoded, pre-validated export document to import.
    ///   - onCollision: How to handle an existing kbite with this code.
    /// - Returns: The import response with resource, file, and keyword counts.
    /// - Throws: Any database error.
    func importApply(
        rehydrated: KbiteExportDocument,
        onCollision: KbiteImportCollision
    ) throws -> KbiteImportResponse {
        let existing = try KbiteRecord
            .filter(KbiteRecord.Columns.code == rehydrated.code)
            .fetchOne(db)?
            .uuid
        if let existing, onCollision == .skip {
            return KbiteImportResponse(
                kbiteUuid: existing,
                code: rehydrated.code,
                imported: false,
                skippedExisting: true,
                resourceCount: 0,
                fileCount: 0,
                keywordCount: 0
            )
        }

        let kbites = KbiteResourceRepository(db: db, core: core)
        let kbiteUuid = try resetKbiteContent(code: rehydrated.code)

        var fileCount = 0
        var attachedKeywords: Set<String> = []
        for resource in rehydrated.resources {
            fileCount += try importResource(
                resource,
                kbiteUuid: kbiteUuid,
                kbites: kbites,
                attachedKeywords: &attachedKeywords
            )
        }
        try attachKbiteKeywords(
            rehydrated.kbiteKeywords,
            kbiteUuid: kbiteUuid,
            kbites: kbites,
            attachedKeywords: &attachedKeywords
        )

        // An overwrite is exactly the import/delete cycle the GC exists
        // for — the previous content's keywords must not orphan forever.
        let gcCount = existing != nil ? try gcOrphanKeywords() : 0

        try core.appendEvent(
            db,
            kind: .kbiteImport,
            subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": rehydrated.code,
                "overwrote_existing": existing != nil,
                "resources": rehydrated.resources.count,
                "files": fileCount,
                "keywords": attachedKeywords.count,
                "gc_keywords": gcCount,
            ])
        )
        return KbiteImportResponse(
            kbiteUuid: kbiteUuid,
            code: rehydrated.code,
            imported: true,
            skippedExisting: false,
            resourceCount: rehydrated.resources.count,
            fileCount: fileCount,
            keywordCount: attachedKeywords.count
        )
    }

    /// Ensures the kbite row exists and clears its content for a fresh import.
    ///
    /// - Parameter code: The kbite code being imported.
    /// - Returns: The stable kbite UUID.
    /// - Throws: Any database error.
    private func resetKbiteContent(code: String) throws -> String {
        let kbiteUuid = try ContextRepository(db: db, core: core).ensureKbite(code: code)
        // Clean-slate content replace under the stable kbite uuid:
        // resources cascade to files + file junctions; the kbite-level
        // keyword junction is cleared explicitly. Registrations survive.
        try db.execute(
            sql: "DELETE FROM kbite_resource WHERE kbite_uuid = ?",
            arguments: [kbiteUuid]
        )
        try db.execute(
            sql: "DELETE FROM kbite_keyword_junction WHERE kbite_uuid = ?",
            arguments: [kbiteUuid]
        )
        return kbiteUuid
    }

    /// Inserts one imported resource and its files under the kbite.
    ///
    /// - Parameters:
    ///   - resource: The resource entry from the export document.
    ///   - kbiteUuid: The owning kbite UUID.
    ///   - kbites: The repository that owns the shared keyword vocabulary.
    ///   - attachedKeywords: Accumulates every keyword text attached so far.
    /// - Returns: The number of files inserted for this resource.
    /// - Throws: Any database error.
    private func importResource(
        _ resource: KbiteExportDocument.Resource,
        kbiteUuid: String,
        kbites: KbiteResourceRepository,
        attachedKeywords: inout Set<String>
    ) throws -> Int {
        let resourceUuid = try core.insertBase(
            db,
            table: "kbite_resource",
            extra: [
                "kbite_uuid": kbiteUuid,
                "resource_name": resource.resourceName,
                "resource_summary": resource.resourceSummary,
                "resource_type": resource.resourceType,
                "resource_trust": resource.resourceTrust,
            ]
        )
        var fileCount = 0
        for file in resource.files {
            try importFile(
                file,
                resourceUuid: resourceUuid,
                kbites: kbites,
                attachedKeywords: &attachedKeywords
            )
            fileCount += 1
        }
        return fileCount
    }

    /// Inserts one imported file and attaches its keywords.
    ///
    /// - Parameters:
    ///   - file: The file entry from the export document.
    ///   - resourceUuid: The owning resource UUID.
    ///   - kbites: The repository that owns the shared keyword vocabulary.
    ///   - attachedKeywords: Accumulates every keyword text attached so far.
    /// - Throws: Any database error.
    private func importFile(
        _ file: KbiteExportDocument.File,
        resourceUuid: String,
        kbites: KbiteResourceRepository,
        attachedKeywords: inout Set<String>
    ) throws {
        let fileUuid = try core.insertBase(
            db,
            table: "kbite_resource_file",
            extra: [
                "kbite_resource_uuid": resourceUuid,
                "resource_file_name": file.resourceFileName,
                "resource_file_summary": file.resourceFileSummary,
                "resource_file_content": file.resourceFileContent,
            ]
        )
        for keyword in file.keywords {
            let keywordUuid = try kbites.ensureKeyword(keyword)
            try kbites.attachKeyword(
                table: "resource_file_keyword_junction",
                ownerColumn: "file_uuid",
                ownerUuid: fileUuid,
                keywordUuid: keywordUuid
            )
            attachedKeywords.insert(keyword)
        }
    }

    /// Attaches the kbite-level keywords from an imported document.
    ///
    /// - Parameters:
    ///   - keywords: The kbite-level keyword texts.
    ///   - kbiteUuid: The owning kbite UUID.
    ///   - kbites: The repository that owns the shared keyword vocabulary.
    ///   - attachedKeywords: Accumulates every keyword text attached so far.
    /// - Throws: Any database error.
    private func attachKbiteKeywords(
        _ keywords: [String],
        kbiteUuid: String,
        kbites: KbiteResourceRepository,
        attachedKeywords: inout Set<String>
    ) throws {
        for keyword in keywords {
            let keywordUuid = try kbites.ensureKeyword(keyword)
            try kbites.attachKeyword(
                table: "kbite_keyword_junction",
                ownerColumn: "kbite_uuid",
                ownerUuid: kbiteUuid,
                keywordUuid: keywordUuid
            )
            attachedKeywords.insert(keyword)
        }
    }

    /// Deletes a kbite and its resources, files, and keywords.
    ///
    /// Registrations cascade with the kbite; event history rows survive
    /// (subject_uuid is not foreign-keyed, preserving append-only ethos).
    /// Orphaned keywords are garbage-collected from the shared vocabulary.
    ///
    /// - Parameter req: The delete request with kbite code.
    /// - Returns: The delete response with counts of deleted entities.
    /// - Throws: `StoreError.notFound` if the kbite code does not exist.
    func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        guard
            let kbiteUuid = try KbiteRecord
                .filter(KbiteRecord.Columns.code == req.code)
                .fetchOne(db)?
                .uuid
        else {
            throw StoreError.notFound(entity: "kbite", key: req.code)
        }
        let counts = try KbiteCounts.request(kbiteUuid: kbiteUuid).fetchOne(db)
        let resources = counts?.resourceCount ?? 0
        let files = counts?.fileCount ?? 0
        let registrations = counts?.registrationCount ?? 0

        // CASCADE clears resources/files/junctions/registrations; the
        // FTS AD triggers keep the mirror consistent (recursive ON).
        try db.execute(sql: "DELETE FROM kbite WHERE uuid = ?", arguments: [kbiteUuid])

        let gcCount = try gcOrphanKeywords()

        try core.appendEvent(
            db,
            kind: .kbiteDelete,
            subjectUuid: kbiteUuid,
            payload: Store.jsonPayload([
                "code": req.code,
                "resources": resources,
                "files": files,
                "registrations": registrations,
                "gc_keywords": gcCount,
            ])
        )
        return KbiteDeleteResponse(
            kbiteUuid: kbiteUuid,
            code: req.code,
            deletedResources: resources,
            deletedFiles: files,
            deletedRegistrations: registrations,
            gcKeywordCount: gcCount
        )
    }

    /// Garbage-collects unreferenced keywords from the shared vocabulary.
    ///
    /// Delete and overwrite operations would otherwise bloat the vocabulary.
    /// Safe as a global sweep because only the two kbite junctions reference
    /// keywords.
    ///
    /// - Returns: The number of keywords deleted.
    /// - Throws: Any database error.
    func gcOrphanKeywords() throws -> Int {
        try db.execute(
            sql: """
                DELETE FROM keyword WHERE uuid NOT IN (
                    SELECT keyword_uuid FROM kbite_keyword_junction
                    UNION SELECT keyword_uuid FROM resource_file_keyword_junction
                )
                """
        )
        return db.changesCount
    }
}
