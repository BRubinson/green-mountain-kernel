import Foundation
import GRDB

// KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE — the portable-kbite family
// over the frozen m0001 tables. Zero migrations: the document is a FILE
// contract (KbiteArchive), not schema. All file I/O happens OUTSIDE the
// write lock (the digestKbite discipline); the daemon touches exactly one
// JSON file at a client-passed absolute path.
// Db phases live in KbiteArchiveRepository; these wrappers own the
// transaction and the file I/O phases.

extension Store {
    /// Assemble the scrubbed export document and write it at
    /// `req.dbExportPath`. Read-only against the db — no event.
    public func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        let (document, fileKeywordCount) = try dbQueue.read { db in
            try KbiteArchiveRepository(db: db, core: core)
                .exportDocument(code: req.code, anonymize: req.anonymize)
        }

        // File write outside the read/write locks; a failed write must not
        // leave a partial document behind (the Backup.swift discipline).
        let destination = URL(fileURLWithPath: req.dbExportPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try KbiteArchive.encode(document).write(to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return KbiteExportResponse(
            kbiteUuid: document.sourceKbiteUuid,
            code: req.code,
            resourceCount: document.resources.count,
            fileCount: document.resources.reduce(0) { $0 + $1.files.count },
            kbiteKeywordCount: document.kbiteKeywords.count,
            fileKeywordCount: fileKeywordCount,
            dbExportPath: destination.path
        )
    }

    /// One-transaction import of a db_export.json (decode + rehydrate happen
    /// outside the write lock; the apply body lives in the repository).
    public func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        // Decode + rehydrate outside the write lock.
        let data = try Data(contentsOf: URL(fileURLWithPath: req.dbExportPath))
        let document = try KbiteArchive.decode(data)
        guard document.formatVersion == KbiteArchive.formatVersion else {
            throw StoreError.badRequest(
                detail: "db_export.json format_version \(document.formatVersion) unsupported "
                + "(this daemon reads \(KbiteArchive.formatVersion))")
        }
        // The one choke point every wire caller passes: an archive code is
        // untrusted input that becomes a path component client-side and a
        // durable kbite row here — a traversal like "../../x" must die now.
        guard KbiteArchive.isValidCode(document.code) else {
            throw StoreError.badRequest(
                detail: "archive kbite code \(String(reflecting: document.code)) is not "
                + "snake_case ([a-z0-9_] only) — refusing to import")
        }
        let rehydrated = document.rehydrated(rules: req.rehydrate)

        return try dbQueue.write { db in
            try KbiteArchiveRepository(db: db, core: core)
                .importApply(rehydrated: rehydrated, onCollision: req.onCollision)
        }
    }

    public func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try dbQueue.write { db in
            try KbiteArchiveRepository(db: db, core: core).deleteKbite(req)
        }
    }
}

extension KbiteExportDocument {
    /// The whole document with placeholder paths mapped back to this
    /// machine's roots across the four text surfaces.
    func rehydrated(rules: [KbitePrefixRule]) -> KbiteExportDocument {
        KbiteExportDocument(
            formatVersion: formatVersion,
            code: code,
            exportedAt: exportedAt,
            sourceKbiteUuid: sourceKbiteUuid,
            kbiteKeywords: kbiteKeywords,
            resources: resources.map { resource in
                Resource(
                    resourceName: resource.resourceName,
                    resourceSummary: KbiteArchive.rehydrate(resource.resourceSummary, rules: rules),
                    resourceType: resource.resourceType,
                    resourceTrust: resource.resourceTrust,
                    files: resource.files.map { file in
                        File(
                            resourceFileName: file.resourceFileName,
                            resourceFileSummary: KbiteArchive.rehydrate(
                                file.resourceFileSummary, rules: rules),
                            resourceFileContent: file.resourceFileContent.map {
                                KbiteArchive.rehydrate($0, rules: rules)
                            },
                            keywords: file.keywords
                        )
                    }
                )
            }
        )
    }
}
