import Foundation
import GRDB

// KBITE_DIGEST / KBITE_GET / KBITE_FILE_GET / KBITE_SEARCH /
// KBITE_KEYWORD_TAG — the digested-content family over the m0002 tables.
// The db is canonical for digested text; the filesystem keeps raw sources
// (re-chewable) and open maws.
// Db bodies live in KbiteResourceRepository; these wrappers own the
// transaction. digestKbite's filesystem phases (maw scan, content pre-read,
// post-commit chewed-file deletion) stay HERE — filesystem work never enters
// a db transaction.

extension Store {
    /// Raw file content larger than this stays filesystem-only (row gets a
    /// NULL content, like binaries).
    private static let maxInlineContentBytes = 2 * 1024 * 1024

    /// The one-step import. Walks {open}/{axis1}/{axis2}/*_chewed.md, parses
    /// each chewed artifact, and writes resource/file/keyword rows in ONE
    /// transaction — re-digesting a resource replaces its previous rows.
    /// Chewed files are deleted only AFTER the commit succeeds (a rollback
    /// never destroys the artifacts); raw sources are always kept.
    public func digestKbite(_ req: KbiteDigestRequest) throws -> KbiteDigestResponse {
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
                            entry.fullPath != nil ? entry : ChewedFileEntry(
                                name: entry.name,
                                type: entry.type,
                                description: entry.description,
                                fullPath: sourceDir.appendingPathComponent(entry.name).path)
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

        let kbiteUuid = try dbQueue.write { db -> String in
            var rc = resourceCount
            var fc = fileCount
            var kw = attachedKeywords
            let uuid = try KbiteResourceRepository(db: db, core: core).digestApply(
                code: req.code, found: found, inlinedContents: inlinedContents,
                resourceCount: &rc, fileCount: &fc, attachedKeywords: &kw)
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

        return KbiteDigestResponse(
            kbiteUuid: kbiteUuid,
            resourceCount: resourceCount,
            fileCount: fileCount,
            keywordCount: attachedKeywords.count,
            deletedChewedFiles: deleted
        )
    }

    /// Full text for text types under the size cap; NULL for everything else
    /// (missing, unreadable, binary, oversized) — the row still exists so the
    /// file is discoverable, the filesystem keeps the raw bytes.
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

    public func getKbite(_ req: KbiteGetRequest) throws -> KbiteGetResponse {
        try dbQueue.read { db in try KbiteResourceRepository(db: db, core: core).getKbite(req) }
    }

    /// The targeted load replacing "cat the chewed file".
    public func getKbiteFile(_ req: KbiteFileGetRequest) throws -> KbiteFileGetResponse {
        try dbQueue.read { db in try KbiteResourceRepository(db: db, core: core).getKbiteFile(req) }
    }

    public func searchKbites(_ req: KbiteSearchRequest) throws -> KbiteSearchResponse {
        guard let pattern = FTS5Pattern(matchingAllTokensIn: req.query) else {
            return KbiteSearchResponse(hits: [])
        }
        return try dbQueue.read { db in
            try KbiteResourceRepository(db: db, core: core).searchKbites(req, pattern: pattern)
        }
    }

    /// Attach/detach normalized keywords at kbite or resource-file level.
    public func tagKeyword(_ req: KbiteKeywordTagRequest) throws -> KbiteKeywordTagResponse {
        try dbQueue.write { db in try KbiteResourceRepository(db: db, core: core).tagKeyword(req) }
    }

    // MARK: - Cross-domain helper forwards (Store+KbiteArchive's import reuses these)

    func ensureKeyword(_ db: Database, _ keyword: String) throws -> String {
        try KbiteResourceRepository(db: db, core: core).ensureKeyword(keyword)
    }

    @discardableResult
    func attachKeyword(
        _ db: Database, table: String, ownerColumn: String, ownerUuid: String, keywordUuid: String
    ) throws -> Bool {
        try KbiteResourceRepository(db: db, core: core).attachKeyword(
            table: table, ownerColumn: ownerColumn, ownerUuid: ownerUuid, keywordUuid: keywordUuid)
    }
}
