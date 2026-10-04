import Foundation
import GRDB

// KBITE_DIGEST / KBITE_GET / KBITE_FILE_GET / KBITE_SEARCH /
// KBITE_KEYWORD_TAG — the digested-content family over the m0002 tables.
// The db is canonical for digested text; the filesystem keeps raw sources
// (re-chewable) and open maws.
// Db bodies live in KbiteResourceRepository; these wrappers own the
// transaction. digestKbite's filesystem phases (maw scan, content pre-read,
// post-commit chewed-file deletion, maw archive) stay HERE — filesystem work
// never enters a db transaction.

extension Store {
    /// Raw file content larger than this stays filesystem-only (row gets a
    /// NULL content, like binaries).
    private static let maxInlineContentBytes = 2 * 1024 * 1024

    /// Digests a kbite maw into resources, files, and keywords in one transaction.
    ///
    /// Walks the maw's chewed artifacts, parses each one, and writes rows in
    /// a single transaction; re-digesting replaces previous rows. Chewed files
    /// are deleted only after commit, so a rollback never destroys artifacts.
    /// Raw sources are then moved to the digested store and the maw dropped.
    ///
    /// - Parameter req: The digest request with maw path and kbite code.
    /// - Returns: Response with resource/file/keyword counts and archive details.
    /// - Throws: `StoreError.notComposable` if called within a transaction.
    func digestKbite(_ req: KbiteDigestRequest) throws -> KbiteDigestResponse {
        // FOUR-PHASE VERB — see StoreError.notComposable. Filesystem work
        // between the read and the write must not hold the single writer.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "digestKbite")
        }
        let fm = FileManager.default
        let openURL = URL(fileURLWithPath: req.kbiteOpenPath, isDirectory: true)

        // Scan the maw up front — pure filesystem, no reason to hold the
        // write lock for it.
        var found: [(artifact: ChewedArtifact, axis1: String, axis2: String, chewedPath: String)] = []
        for axis1 in ["primary", "secondary"] {
            for axis2 in ["documentation", "example_project", "api_reference", "blogs", "all_others"] {
                let dir = openURL.appendingPathComponent(axis1, isDirectory: true)
                    .appendingPathComponent(axis2, isDirectory: true)
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for name in names.sorted() where name.hasSuffix("_chewed.md") {
                    let chewedURL = dir.appendingPathComponent(name)
                    guard let text = try? String(contentsOf: chewedURL, encoding: .utf8) else { continue }
                    let fallback = String(name.dropLast("_chewed.md".count))
                    var artifact = ChewedArtifactParser.parse(text: text, fallbackName: fallback)
                    // Entries with no absolute path resolve against the
                    // sibling raw-source folder ({axis2}/{resource_name}/).
                    let sourceDir = dir.appendingPathComponent(artifact.resourceName, isDirectory: true)
                    artifact = ChewedArtifact(
                        resourceName: artifact.resourceName,
                        confidence: artifact.confidence,
                        body: artifact.body,
                        files: artifact.files.map { entry in
                            entry.fullPath != nil
                                ? entry
                                : ChewedFileEntry(
                                    name: entry.name,
                                    type: entry.type,
                                    description: entry.description,
                                    fullPath: sourceDir.appendingPathComponent(entry.name).path
                                )
                        },
                        keywords: artifact.keywords
                    )
                    found.append((artifact, axis1, axis2, chewedURL.path))
                }
            }
        }

        // Raw-source content is also read up front — inlineContent stats and
        // reads up to 2 MB per file, which must not happen while the single
        // serialized connection holds the write lock.
        let inlinedContents: [[String?]] = found.map { item in
            item.artifact.files.map { self.inlineContent($0) }
        }

        var resourceCount = 0
        var fileCount = 0
        var attachedKeywords: Set<String> = []

        let kbiteUuid = try boundary { db -> String in
            var rc = resourceCount
            var fc = fileCount
            var kw = attachedKeywords
            let uuid = try KbiteResourceRepository(db: db, core: core)
                .digestApply(
                    code: req.code,
                    found: found,
                    inlinedContents: inlinedContents,
                    resourceCount: &rc,
                    fileCount: &fc,
                    attachedKeywords: &kw
                )
            resourceCount = rc
            fileCount = fc
            attachedKeywords = kw
            return uuid
        }

        // Commit succeeded — now (and only now) the temporary chewed files go.
        var deleted: [String] = []
        for item in found where (try? fm.removeItem(atPath: item.chewedPath)) != nil {
            deleted.append(item.chewedPath)
        }

        // An empty digest leaves the maw where it is: moving un-chewed sources
        // into the archive would strand them somewhere no chew step looks.
        var archivedTo: String?
        var archiveError: String?
        if resourceCount > 0 {
            do {
                archivedTo = try archiveMaw(openURL, code: req.code).path
            } catch {
                archiveError = String(describing: error)
            }
        }

        return KbiteDigestResponse(
            kbiteUuid: kbiteUuid,
            resourceCount: resourceCount,
            fileCount: fileCount,
            keywordCount: attachedKeywords.count,
            deletedChewedFiles: deleted,
            archivedTo: archivedTo,
            archiveError: archiveError
        )
    }

    /// Moves the maw to the digested store and removes the empty maw.
    ///
    /// A re-digest merges over the earlier archive file by file, so a
    /// partial re-chew replaces only the resources it carried.
    ///
    /// - Parameters:
    ///   - openURL: The path to the open maw to archive.
    ///   - code: The kbite code for the destination directory.
    /// - Returns: The URL of the digested archive directory.
    /// - Throws: Any filesystem error during the move.
    private func archiveMaw(_ openURL: URL, code: String) throws -> URL {
        let destination = Paths.kbitesDigestedRoot.appendingPathComponent(code, isDirectory: true)
        try Paths.assertContained(openURL)
        try Paths.assertContained(destination)
        try Self.mergeMove(from: openURL, to: destination)
        try FileManager.default.removeItem(at: openURL)
        return destination
    }

    /// Recursively moves files and directories from source to destination.
    ///
    /// - Parameters:
    ///   - source: The source directory to move from.
    ///   - destination: The destination directory to move to (created if needed).
    /// - Throws: Any filesystem error during the move.
    private static func mergeMove(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: from.path, isDirectory: &isDir)
            if isDir.boolValue {
                try mergeMove(from: from, to: to)
            } else {
                if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                try fm.moveItem(at: from, to: to)
            }
        }
    }

    /// Returns full text for small text-type files, or nil otherwise.
    ///
    /// Files above the size cap, non-text types, missing, unreadable, or
    /// binary files return nil; the row still exists so the file remains
    /// discoverable while the filesystem keeps the raw bytes.
    ///
    /// - Parameter entry: The chewed file entry to read.
    /// - Returns: The file text, or nil.
    private func inlineContent(_ entry: ChewedFileEntry) -> String? {
        guard let path = entry.fullPath, ChewedArtifactParser.isTextType(fileName: entry.name) else {
            return nil
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attrs?[.size] as? Int, size > Store.maxInlineContentBytes {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Retrieves kbite resource metadata and inline content.
    ///
    /// - Parameter req: The request with kbite UUID.
    /// - Returns: The resource response with metadata and content.
    /// - Throws: Any database error.
    func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        try boundaryRead { db in try KbiteResourceRepository(db: db, core: core).getKbite(req) }
    }

    /// Retrieves a single file from a kbite resource with inline content.
    ///
    /// - Parameter req: The request with resource UUID and file name.
    /// - Returns: The file response with metadata and content.
    /// - Throws: Any database error.
    func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        try boundaryRead { db in try KbiteResourceRepository(db: db, core: core).getKbiteFile(req) }
    }

    /// Searches kbite resources by full-text query.
    ///
    /// - Parameter req: The search request with query string.
    /// - Returns: The search response with matching resources.
    /// - Throws: Any database error.
    func searchKbites(_ req: KbiteSearchRequest) throws -> KbiteSearchResponse {
        // ORs the query tokens (see Store+DopeSearch for why AND was wrong).
        // The empty-hit-list answer to an untokenizable query is a DELIBERATE
        // divergence from DOPE_SEARCH and SEARCH, which throw badRequest; it
        // predates this change and is left alone.
        guard let pattern = FTS5Pattern(matchingAnyTokenIn: req.query) else {
            return KbiteSearchResponse(hits: [])
        }
        return try boundaryRead { db in
            try KbiteResourceRepository(db: db, core: core).searchKbites(req, pattern: pattern)
        }
    }

    /// Attaches or detaches keywords from kbite resources or files.
    ///
    /// - Parameter req: The tag request with target, keyword, and action.
    /// - Returns: The response with keyword association details.
    /// - Throws: Any database error.
    func tagKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        try boundary { db in try KbiteResourceRepository(db: db, core: core).tagKeyword(req) }
    }

    // MARK: - Cross-domain helper forwards (Store+KbiteArchive's import reuses these)

    /// Gets or creates a keyword, returning its UUID.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - keyword: The keyword string to ensure.
    /// - Returns: The UUID of the keyword.
    /// - Throws: Any database error.
    func ensureKeyword(_ db: Database, _ keyword: String) throws -> String {
        try KbiteResourceRepository(db: db, core: core).ensureKeyword(keyword)
    }

    /// Attaches a keyword to a resource or file.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - table: The name of the table owning the resource.
    ///   - ownerColumn: The column name holding the owner UUID.
    ///   - ownerUuid: The UUID of the owner (resource or file).
    ///   - keywordUuid: The UUID of the keyword to attach.
    /// - Returns: True if the attachment was new, false if it already existed.
    /// - Throws: Any database error.
    @discardableResult
    func attachKeyword(
        _ db: Database,
        table: String,
        ownerColumn: String,
        ownerUuid: String,
        keywordUuid: String
    ) throws -> Bool {
        try KbiteResourceRepository(db: db, core: core)
            .attachKeyword(
                table: table,
                ownerColumn: ownerColumn,
                ownerUuid: ownerUuid,
                keywordUuid: keywordUuid
            )
    }
}
