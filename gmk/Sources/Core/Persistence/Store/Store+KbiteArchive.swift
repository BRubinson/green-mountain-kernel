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
    /// Exports a kbite to a file on disk.
    ///
    /// Assemble the scrubbed export document and write it at
    /// `req.dbExportPath`.
    ///
    /// Read-only against the db — no event.
    ///
    /// - Parameter req: The export request with code and paths.
    /// - Returns: The export response with counts and written path.
    /// - Throws: `StoreError` for invalid requests or file I/O errors.
    func exportKbite(_ req: KbiteExportRequest) throws -> KbiteExportResponse {
        // FOUR-PHASE VERB — see StoreError.notComposable. Filesystem work
        // between the read and the write must not hold the single writer.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "exportKbite")
        }
        let (document, fileKeywordCount) = try boundaryRead { db in
            try KbiteArchiveRepository(db: db, core: core)
                .exportDocument(code: req.code, anonymize: req.anonymize)
        }

        // File write outside the read/write locks; a failed write must not
        // leave a partial document behind (the Backup.swift discipline).
        let destination = URL(fileURLWithPath: req.dbExportPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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

    /// Imports a kbite from an exported archive file.
    ///
    /// One-transaction import of a db_export.json (decode + rehydrate happen
    /// outside the write lock; the apply body lives in the repository).
    ///
    /// - Parameter req: The import request with file path and rehydration rules.
    /// - Returns: The import response with counts and created kbite uuid.
    /// - Throws: `StoreError` for invalid formats or collision handling.
    func importKbite(_ req: KbiteImportRequest) throws -> KbiteImportResponse {
        // FOUR-PHASE VERB — see StoreError.notComposable. Filesystem work
        // between the read and the write must not hold the single writer.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "importKbite")
        }
        // Decode + rehydrate outside the write lock.
        let data = try Data(contentsOf: URL(fileURLWithPath: req.dbExportPath))
        let document = try KbiteArchive.decode(data)
        guard document.formatVersion == KbiteArchive.formatVersion else {
            throw StoreError.badRequest(
                detail: "db_export.json format_version \(document.formatVersion) unsupported "
                    + "(this daemon reads \(KbiteArchive.formatVersion))"
            )
        }
        // The one choke point every wire caller passes: an archive code is
        // untrusted input that becomes a path component client-side and a
        // durable kbite row here — a traversal like "../../x" must die now.
        guard KbiteArchive.isValidCode(document.code) else {
            throw StoreError.badRequest(
                detail: "archive kbite code \(String(reflecting: document.code)) is not "
                    + "snake_case ([a-z0-9_] only) — refusing to import"
            )
        }
        let rehydrated = document.rehydrated(rules: req.rehydrate)

        return try boundary { db in
            try KbiteArchiveRepository(db: db, core: core)
                .importApply(rehydrated: rehydrated, onCollision: req.onCollision)
        }
    }

    /// Deletes a kbite from the database.
    ///
    /// - Parameter req: The delete request with the kbite uuid.
    /// - Returns: The delete response.
    /// - Throws: Database errors or `StoreError`.
    func deleteKbite(_ req: KbiteDeleteRequest) throws -> KbiteDeleteResponse {
        try boundary { db in
            try KbiteArchiveRepository(db: db, core: core).deleteKbite(req)
        }
    }
}

extension KbiteExportDocument {
    /// Returns a copy with placeholder paths rehydrated to machine roots.
    ///
    /// The whole document with placeholder paths mapped back to this
    /// machine's roots across the four text surfaces.
    ///
    /// - Parameter rules: The prefix rules to apply during rehydration.
    /// - Returns: A new document with rehydrated paths.
    func rehydrated(rules: [KbitePrefixRule]) -> KbiteExportDocument {
        KbiteExportDocument(
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
                                file.resourceFileSummary,
                                rules: rules
                            ),
                            resourceFileContent: file.resourceFileContent.map {
                                KbiteArchive.rehydrate($0, rules: rules)
                            },
                            keywords: file.keywords
                        )
                    }
                )
            },
            formatVersion: formatVersion
        )
    }
}
