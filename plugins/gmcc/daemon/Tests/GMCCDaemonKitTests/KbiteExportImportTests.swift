import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The portable-kbite family end-to-end against a temp db: scrub/rehydrate
/// codec, export → delete → import round-trip parity, collision policies,
/// registration survival under overwrite, cascade + keyword GC.
final class KbiteExportImportTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbite-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        dbPath = workDir.appendingPathComponent("test.db").path
        store = try Store(path: dbPath)
        try store.migrate()
        // Minimal context chain so a session registration row can exist.
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1',
                        '/tmp/repo', 'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: workDir)
    }

    // MARK: - Fixtures

    private func fixtureDocument(code: String = "fixture_kbite") -> KbiteExportDocument {
        KbiteExportDocument(
            code: code,
            exportedAt: Store.isoNow(),
            sourceKbiteUuid: "source-machine-uuid",
            kbiteKeywords: ["alpha", "shared_word"],
            resources: [
                KbiteExportDocument.Resource(
                    resourceName: "guide",
                    resourceSummary: "Docs at {{KBITE_TREE}}/primary/documentation/guide",
                    resourceType: "documentation",
                    resourceTrust: 0,
                    files: [
                        KbiteExportDocument.File(
                            resourceFileName: "binary.png",
                            resourceFileSummary: "a binary — content stays NULL",
                            resourceFileContent: nil,
                            keywords: ["alpha"]),
                        KbiteExportDocument.File(
                            resourceFileName: "intro.md",
                            resourceFileSummary: "the intro",
                            resourceFileContent: "clone under {{GMCC_HOME}}/work and read",
                            keywords: ["alpha", "intro_word"]),
                    ]),
                KbiteExportDocument.Resource(
                    resourceName: "reference",
                    resourceSummary: "secondary api notes",
                    resourceType: "api_reference",
                    resourceTrust: 100,
                    files: [
                        KbiteExportDocument.File(
                            resourceFileName: "api.md",
                            resourceFileSummary: "endpoints",
                            resourceFileContent: "GET /things returns things",
                            keywords: ["shared_word"]),
                    ]),
            ])
    }

    private func writeDocument(_ document: KbiteExportDocument, name: String) throws -> String {
        let url = workDir.appendingPathComponent(name)
        try KbiteArchive.encode(document).write(to: url)
        return url.path
    }

    private func importFixture(
        code: String = "fixture_kbite",
        onCollision: KbiteImportCollision = .skip
    ) throws -> KbiteImportResponse {
        let path = try writeDocument(fixtureDocument(code: code), name: "import-\(UUID().uuidString).json")
        return try store.importKbite(KbiteImportRequest(
            dbExportPath: path, onCollision: onCollision, rehydrate: [
                KbitePrefixRule(
                    prefix: "/machines/two/kbites/digested/\(code)",
                    placeholder: KbiteArchive.treePlaceholder),
                KbitePrefixRule(prefix: "/Users/two", placeholder: KbiteArchive.homePlaceholder),
            ]))
    }

    // MARK: - Codec

    func testScrubIsLongestPrefixFirstAndRehydrateInverts() {
        let scrubRules = [
            KbitePrefixRule(prefix: "/Users/one", placeholder: KbiteArchive.homePlaceholder),
            KbitePrefixRule(
                prefix: "/Users/one/ckfs/kbites/open/demo", placeholder: KbiteArchive.treePlaceholder),
        ]
        let text = "maw at /Users/one/ckfs/kbites/open/demo/primary, home at /Users/one/notes"
        let scrubbed = KbiteArchive.scrub(text, rules: scrubRules)
        XCTAssertEqual(
            scrubbed,
            "maw at \(KbiteArchive.treePlaceholder)/primary, home at \(KbiteArchive.homePlaceholder)/notes",
            "the longer kbite-tree prefix must win over the $HOME prefix it contains")

        let rehydrated = KbiteArchive.rehydrate(scrubbed, rules: [
            KbitePrefixRule(
                prefix: "/machines/two/digested/demo", placeholder: KbiteArchive.treePlaceholder),
            KbitePrefixRule(prefix: "/Users/two", placeholder: KbiteArchive.homePlaceholder),
        ])
        XCTAssertEqual(
            rehydrated, "maw at /machines/two/digested/demo/primary, home at /Users/two/notes")
    }

    func testDocumentEncodeDecodePreservesNullContent() throws {
        let document = fixtureDocument()
        let decoded = try KbiteArchive.decode(KbiteArchive.encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertNil(decoded.resources[0].files[0].resourceFileContent)
    }

    // MARK: - Import

    func testImportCreatesRowsAndRemapsKeywordsByText() throws {
        // Pre-seed one shared keyword so import must reuse, not duplicate.
        try store.dbQueue.write { db in
            _ = try self.store.ensureKeyword(db, "shared_word")
        }
        let response = try importFixture()
        XCTAssertTrue(response.imported)
        XCTAssertEqual(response.resourceCount, 2)
        XCTAssertEqual(response.fileCount, 3)

        let kbite = try store.getKbite(KbiteGetRequest(code: "fixture_kbite"))
        XCTAssertEqual(kbite.keywords, ["alpha", "shared_word"])
        XCTAssertEqual(kbite.resources.count, 2)
        let shared = try store.dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM keyword WHERE keyword = 'shared_word'") ?? 0
        }
        XCTAssertEqual(shared, 1, "keywords must remap by TEXT, never duplicate the shared vocabulary")

        // Rehydration reached the content: placeholder became the local root.
        let intro = kbite.resources[0].files.first { $0.resourceFileName == "intro.md" }!
        let content = try store.getKbiteFile(
            KbiteFileGetRequest(fileUuid: intro.uuid)).file.resourceFileContent
        XCTAssertEqual(content, "clone under /Users/two/work and read")
        // FTS stayed consistent through plain inserts.
        let hits = try store.searchKbites(KbiteSearchRequest(query: "endpoints"))
        XCTAssertEqual(hits.hits.count, 1)
    }

    func testImportSkipCollisionLeavesExistingUntouched() throws {
        _ = try importFixture()
        let before = try store.getKbite(KbiteGetRequest(code: "fixture_kbite"))
        let second = try importFixture(onCollision: .skip)
        XCTAssertFalse(second.imported)
        XCTAssertTrue(second.skippedExisting)
        let after = try store.getKbite(KbiteGetRequest(code: "fixture_kbite"))
        XCTAssertEqual(before.kbite.uuid, after.kbite.uuid)
        XCTAssertEqual(before.resources.map(\.uuid), after.resources.map(\.uuid))
    }

    func testOverwritePreservesKbiteUuidAndRegistrations() throws {
        let first = try importFixture()
        let kbiteUuid = first.kbiteUuid
        try store.dbQueue.write { db in
            _ = try self.store.insertBase(db, table: "session_active_kbite", extra: [
                "session_uuid": "sess-1", "kbite_uuid": kbiteUuid,
            ])
        }
        let second = try importFixture(onCollision: .overwrite)
        XCTAssertTrue(second.imported)
        XCTAssertEqual(second.kbiteUuid, kbiteUuid,
                       "overwrite must reuse the existing kbite uuid")
        let registrations = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM session_active_kbite WHERE kbite_uuid = ?",
                arguments: [kbiteUuid]) ?? 0
        }
        XCTAssertEqual(registrations, 1, "scope registrations must survive overwrite")
        // No stale duplicates: still exactly the document's resources.
        let kbite = try store.getKbite(KbiteGetRequest(code: "fixture_kbite"))
        XCTAssertEqual(kbite.resources.count, 2)
    }

    func testImportRejectsPathTraversalCode() throws {
        XCTAssertFalse(KbiteArchive.isValidCode("../../../Users/x/target"))
        XCTAssertFalse(KbiteArchive.isValidCode("has space"))
        XCTAssertFalse(KbiteArchive.isValidCode(""))
        XCTAssertFalse(KbiteArchive.isValidCode("Upper_Case"))
        XCTAssertTrue(KbiteArchive.isValidCode("claude_customization2"))

        let document = KbiteExportDocument(
            code: "../evil", exportedAt: Store.isoNow(),
            sourceKbiteUuid: "x", kbiteKeywords: [], resources: [])
        let path = try writeDocument(document, name: "evil.json")
        XCTAssertThrowsError(try store.importKbite(KbiteImportRequest(
            dbExportPath: path, onCollision: .skip, rehydrate: []))) { error in
            guard case StoreError.badRequest = error else {
                return XCTFail("expected badRequest, got \(error)")
            }
        }
        let kbites = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kbite") ?? -1
        }
        XCTAssertEqual(kbites, 0, "a rejected code must never reach ensureKbite")
    }

    func testOverwriteImportGarbageCollectsPreviousKeywords() throws {
        _ = try importFixture()
        // Overwrite with a document whose keyword set no longer contains the
        // old vocabulary — the orphans must be swept in the same import.
        var slim = fixtureDocument()
        slim = KbiteExportDocument(
            code: slim.code, exportedAt: slim.exportedAt,
            sourceKbiteUuid: slim.sourceKbiteUuid,
            kbiteKeywords: ["fresh_word"],
            resources: [KbiteExportDocument.Resource(
                resourceName: "guide", resourceSummary: "slimmed",
                resourceType: "documentation", resourceTrust: 0,
                files: [KbiteExportDocument.File(
                    resourceFileName: "intro.md", resourceFileSummary: "s",
                    resourceFileContent: "x", keywords: ["fresh_word"])])])
        let path = try writeDocument(slim, name: "slim.json")
        _ = try store.importKbite(KbiteImportRequest(
            dbExportPath: path, onCollision: .overwrite, rehydrate: []))
        let keywords = try store.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT keyword FROM keyword ORDER BY keyword")
        }
        XCTAssertEqual(keywords, ["fresh_word"],
                       "overwrite must GC the previous content's orphaned keywords")
    }

    func testImportRejectsUnknownFormatVersion() throws {
        let document = KbiteExportDocument(
            formatVersion: 99, code: "future_kbite", exportedAt: Store.isoNow(),
            sourceKbiteUuid: "x", kbiteKeywords: [], resources: [])
        let path = try writeDocument(document, name: "future.json")
        XCTAssertThrowsError(try store.importKbite(KbiteImportRequest(
            dbExportPath: path, onCollision: .skip, rehydrate: [])))
    }

    // MARK: - Export + round trip

    func testExportScrubsAndRoundTripsAfterDelete() throws {
        _ = try importFixture()
        // Export with a rule that matches the rehydrated local content.
        let exportPath = workDir.appendingPathComponent("db_export.json").path
        let response = try store.exportKbite(KbiteExportRequest(
            code: "fixture_kbite", dbExportPath: exportPath,
            anonymize: [KbitePrefixRule(prefix: "/Users/two", placeholder: KbiteArchive.homePlaceholder)]))
        XCTAssertEqual(response.resourceCount, 2)
        XCTAssertEqual(response.fileCount, 3)
        XCTAssertEqual(response.kbiteKeywordCount, 2)

        let exported = try KbiteArchive.decode(
            try Data(contentsOf: URL(fileURLWithPath: exportPath)))
        let intro = exported.resources
            .first { $0.resourceName == "guide" }!.files
            .first { $0.resourceFileName == "intro.md" }!
        XCTAssertEqual(intro.resourceFileContent,
                       "clone under \(KbiteArchive.homePlaceholder)/work and read",
                       "export must scrub machine roots back to placeholders")
        XCTAssertNil(exported.resources
            .first { $0.resourceName == "guide" }!.files
            .first { $0.resourceFileName == "binary.png" }!.resourceFileContent,
            "NULL content must stay NULL through export")

        // delete → re-import the export → parity.
        _ = try store.deleteKbite(KbiteDeleteRequest(code: "fixture_kbite"))
        let again = try store.importKbite(KbiteImportRequest(
            dbExportPath: exportPath, onCollision: .skip,
            rehydrate: [KbitePrefixRule(prefix: "/Users/two", placeholder: KbiteArchive.homePlaceholder)]))
        XCTAssertTrue(again.imported)
        let kbite = try store.getKbite(KbiteGetRequest(code: "fixture_kbite"))
        XCTAssertEqual(kbite.resources.count, 2)
        XCTAssertEqual(kbite.keywords, ["alpha", "shared_word"])
        XCTAssertEqual(try store.searchKbites(KbiteSearchRequest(query: "endpoints")).hits.count, 1)
    }

    func testExportUnknownCodeIsNotFound() {
        XCTAssertThrowsError(try store.exportKbite(KbiteExportRequest(
            code: "no_such_kbite",
            dbExportPath: workDir.appendingPathComponent("x.json").path,
            anonymize: [])))
    }

    // MARK: - Delete

    func testDeleteCascadesAndGarbageCollectsKeywords() throws {
        // Two kbites sharing the same vocabulary: deleting one must GC
        // nothing; deleting the last referrer sweeps the words.
        let response = try importFixture()
        _ = try importFixture(code: "other_kbite")
        let kbiteUuid = response.kbiteUuid
        try store.dbQueue.write { db in
            _ = try self.store.insertBase(db, table: "session_active_kbite", extra: [
                "session_uuid": "sess-1", "kbite_uuid": kbiteUuid,
            ])
        }

        let deleted = try store.deleteKbite(KbiteDeleteRequest(code: "fixture_kbite"))
        XCTAssertEqual(deleted.deletedResources, 2)
        XCTAssertEqual(deleted.deletedFiles, 3)
        XCTAssertEqual(deleted.deletedRegistrations, 1)
        XCTAssertEqual(deleted.gcKeywordCount, 0,
                       "words still referenced by other_kbite must survive the GC")
        let midKeywords = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keyword") ?? -1
        }
        XCTAssertEqual(midKeywords, 3)  // alpha, shared_word, intro_word

        let last = try store.deleteKbite(KbiteDeleteRequest(code: "other_kbite"))
        XCTAssertEqual(last.gcKeywordCount, 3)

        let counts = try store.dbQueue.read { db -> (Int, Int, Int, Int, Int) in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kbite") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kbite_resource") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kbite_resource_file") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session_active_kbite") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keyword") ?? -1)
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        XCTAssertEqual(counts.2, 0)
        XCTAssertEqual(counts.3, 0, "registrations drop with the kbite — desired for delete")
        XCTAssertEqual(counts.4, 0)
        XCTAssertEqual(try store.searchKbites(KbiteSearchRequest(query: "endpoints")).hits.count, 0,
                       "FTS mirror must be consistent after the cascade")
    }
}
