import XCTest
import GRDB
@testable import GMCCDaemonKit

/// End-to-end over the three whole-tree repo verbs against a temp git
/// checkout: init → build tree → write-repo → read-repo → ingest, plus both
/// directions of the revision gates.
final class DopeRepoVerbTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true)
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-repo-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
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
                        '\(repoRoot.path)', 'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(at: repoRoot)
    }

    private func makeScopeWithTree() throws -> DopeScopeRow {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let domain = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        let en = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .enumeration, parentUuid: domain.uuid,
            fields: DopeNodeFields(code: "status", name: "Status")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .option, parentUuid: en.uuid,
            fields: DopeNodeFields(code: "active", name: "Active")))
        let id = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .uuid,
                                   nullable: false, isUnique: true)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "state", name: "State", dataType: .enumeration,
                                   enumUuid: en.uuid)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "owner", name: "Owner", dataType: .relationship,
                                   relationshipTargetUuid: id.uuid)))
        return try store.dbQueue.read { db in
            try self.store.fetchDopeScope(db, uuid: scope.uuid)!
        }
    }

    // MARK: - merge provenance (the base)

    /// End-to-end: a real edit through the real verbs must show up as a
    /// dirty dot-path, and a sync from files must clear it and record the
    /// base. Without this the merge has nothing true to reason about.
    func testProvenanceTracksLocalEditsAndIsClearedByIngest() throws {
        let scope = try makeScopeWithTree()

        // Granular edits mark their own dot-paths, addressed the way dope
        // refs address them.
        let dirty = try store.dbQueue.read { db in
            try self.store.locallyModifiedPaths(db, scopeUuid: scope.uuid)
        }
        XCTAssertTrue(dirty.contains("core.user"), "entity add should mark core.user: \(dirty)")
        XCTAssertTrue(dirty.contains("core.user.id"), "property add should mark it: \(dirty)")
        XCTAssertTrue(dirty.contains("core.enums.status.active"),
                      "option add should mark it: \(dirty)")

        // Publish, then re-ingest: the tree now came FROM the files, so the
        // base is recorded and nothing is dirty any more.
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let bumped = DopeDocumentBundle(
            main: DopeScopeDocument(version: scope.revision + 1, scope: read.main.scope,
                                    persistence: read.main.persistence),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: scope.revision + 1, body: $0.body,
                                            entities: $0.entities, enums: $0.enums)
            })
        _ = try sandbox.writeAtomically(bumped)
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))

        let afterSync = try store.dbQueue.read { db in
            try self.store.locallyModifiedPaths(db, scopeUuid: scope.uuid)
        }
        XCTAssertTrue(afterSync.isEmpty, "sync must clear dirty flags, got \(afterSync)")

        let base = try store.dbQueue.read { db in
            try self.store.dopeProvenance(db, scopeUuid: scope.uuid)
        }
        XCTAssertNotNil(base["core.user"]?.syncedContentHash,
                        "the base hash must be recorded for every synced element")
        XCTAssertEqual(base["core.user"]?.locallyModified, false)

        // And the recorded base must agree with what a fresh read hashes —
        // otherwise the very next boundary would report phantom conflicts.
        let theirs = DopeMerge.elements(of: try sandbox.readBundle().bundle)
        let plan = DopeMerge.plan(
            ours: theirs, theirs: theirs,
            base: try store.dbQueue.read { db in
                try self.store.dopeProvenance(db, scopeUuid: scope.uuid)
            })
        XCTAssertTrue(DopeMerge.conflicts(in: plan).isEmpty,
                      "a freshly synced tree must merge clean against itself")
    }

    // MARK: - conflict detection and resolution

    /// Drives a real conflict end-to-end: publish, sync to establish a base,
    /// edit BOTH sides, and confirm the plan reports exactly the conflicting
    /// path — then resolve it each way and confirm it clears in the
    /// direction chosen.
    func testConflictIsDetectedThenResolvedInEitherDirection() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)

        // Establish the base: this tree came from the files.
        let published = try sandbox.readBundle().bundle
        let rebased = DopeDocumentBundle(
            main: DopeScopeDocument(version: scope.revision + 1, scope: published.main.scope,
                                    persistence: published.main.persistence),
            domainFiles: published.domainFiles.map {
                DopePersistenceFileDocument(version: scope.revision + 1, body: $0.body,
                                            entities: $0.entities, enums: $0.enums)
            })
        _ = try sandbox.writeAtomically(rebased)
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertTrue(DopeMerge.conflicts(in:
            try store.dopeMergePlan(scopeUuid: scope.uuid)).isEmpty,
            "a freshly synced tree must be conflict-free")

        // OUR side: edit the entity through the real verb.
        let entityUuid = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM dope_persistence_entity WHERE code = 'user'
                """)
        }
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: entityUuid!, expectedVersion: 0,
            fields: DopeNodeFields(name: "User (ours)")))

        // THEIR side: the same element moves on disk.
        let current = try sandbox.readBundle().bundle
        let theirDomains = current.domainFiles.map { file in
            DopePersistenceFileDocument(
                version: file.version + 1, body: file.body,
                entities: file.entities.map { entity in
                    entity.body.code == "user"
                        ? DopeEntityDocument(
                            body: DopeEntityBody(
                                code: entity.body.code, name: "User (theirs)",
                                entityType: entity.body.entityType,
                                description: entity.body.description,
                                sortOrder: entity.body.sortOrder,
                                repoRepresentativeFile: entity.body.repoRepresentativeFile,
                                baseComposableRef: entity.body.baseComposableRef),
                            properties: entity.properties)
                        : entity
                },
                enums: file.enums)
        }
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: current.main.version + 1,
                                    scope: current.main.scope,
                                    persistence: current.main.persistence),
            domainFiles: theirDomains))

        // Both moved → exactly one conflict, named by dot-path.
        let conflicts = DopeMerge.conflicts(in: try store.dopeMergePlan(scopeUuid: scope.uuid))
        XCTAssertEqual(conflicts.map(\.dotPath), ["core.user"])

        // Resolve toward THEIRS: the file wins on the next plan.
        XCTAssertEqual(
            try store.dopeResolve(scopeUuid: scope.uuid, dotPath: "core.user", takeOurs: false),
            ["core.user"])
        let afterTheirs = try store.dopeMergePlan(scopeUuid: scope.uuid)
        XCTAssertTrue(DopeMerge.conflicts(in: afterTheirs).isEmpty)
        XCTAssertEqual(afterTheirs.first { $0.dotPath == "core.user" }?.decision, .takeTheirs)
    }

    func testResolveTowardOursKeepsTheLocalEdit() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let published = try sandbox.readBundle().bundle
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: scope.revision + 1, scope: published.main.scope,
                                    persistence: published.main.persistence),
            domainFiles: published.domainFiles.map {
                DopePersistenceFileDocument(version: scope.revision + 1, body: $0.body,
                                            entities: $0.entities, enums: $0.enums)
            }))
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))

        let entityUuid = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT uuid FROM dope_persistence_entity WHERE code = 'user'
                """)
        }
        _ = try store.dopeNodeUpdate(DopeNodeUpdateRequest(
            level: .entity, nodeUuid: entityUuid!, expectedVersion: 0,
            fields: DopeNodeFields(name: "User (ours)")))

        let current = try sandbox.readBundle().bundle
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: current.main.version + 1,
                                    scope: current.main.scope,
                                    persistence: current.main.persistence),
            domainFiles: current.domainFiles.map { file in
                DopePersistenceFileDocument(
                    version: file.version + 1, body: file.body,
                    entities: file.entities.map { entity in
                        entity.body.code == "user"
                            ? DopeEntityDocument(
                                body: DopeEntityBody(
                                    code: entity.body.code, name: "User (theirs)",
                                    entityType: entity.body.entityType,
                                    description: entity.body.description,
                                    sortOrder: entity.body.sortOrder,
                                    repoRepresentativeFile: entity.body.repoRepresentativeFile,
                                    baseComposableRef: entity.body.baseComposableRef),
                                properties: entity.properties)
                            : entity
                    },
                    enums: file.enums)
            }))

        XCTAssertEqual(
            DopeMerge.conflicts(in: try store.dopeMergePlan(scopeUuid: scope.uuid))
                .map(\.dotPath),
            ["core.user"])

        // Resolve with no path = every conflict, toward ours.
        XCTAssertEqual(
            try store.dopeResolve(scopeUuid: scope.uuid, dotPath: nil, takeOurs: true),
            ["core.user"])
        let after = try store.dopeMergePlan(scopeUuid: scope.uuid)
        XCTAssertTrue(DopeMerge.conflicts(in: after).isEmpty)
        XCTAssertEqual(after.first { $0.dotPath == "core.user" }?.decision, .keepOurs)
    }

    // MARK: - tombstones never project

    /// Directly proves the projection filter, independent of the two gates
    /// that currently make a tombstone unreachable from the write path
    /// (soft-delete is overlay-only, repo verbs are session-base-only).
    /// Those gates are disjoint today; this asserts the invariant holds on
    /// its own merits, so relaxing either one cannot quietly start writing
    /// tombstones into committed files.
    func testProjectionFilterDropsSoftDeletedRows() throws {
        let scope = try makeScopeWithTree()

        // Soft-delete is refused outside an overlay, so stamp deleted_on
        // directly — this is exactly the state the filter must survive.
        try store.dbQueue.write { db in
            try db.execute(sql: """
                UPDATE dope_persistence_entity SET deleted_on = '2026-01-01T00:00:00Z'
                 WHERE code = 'user'
                """)
        }

        let unfiltered = try store.dbQueue.read { db in
            try self.store.fetchDopeTree(db, scope: scope)
        }
        let projected = try store.dbQueue.read { db in
            try self.store.fetchDopeTree(db, scope: scope, forProjection: true)
        }

        func hasUserEntity(_ tree: DopeScopeTree) -> Bool {
            for domain in tree.domains {
                for entity in domain.entities where entity.body.code == "user" { return true }
            }
            return false
        }
        XCTAssertTrue(
            hasUserEntity(unfiltered),
            "an unfiltered read must still see the tombstone — the resolver depends on it")
        XCTAssertFalse(
            hasUserEntity(projected),
            "the projection must drop the tombstoned entity")
    }

    // MARK: - session-base-only gate

    /// Creates a PROMPT-tier (SESSION_INSTANCE_ITEM) scope alongside the
    /// session-base one. Before the gate existed, all three repo verbs
    /// happily resolved this scope's instance root — the same root the
    /// session-base tree lives at — and wrote a prompt tree over the shared
    /// .gmcc, tombstones and all.
    private func makeOverlayScope() throws -> DopeScopeRow {
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command,
                    status, ckfs_relative_storage_path)
                VALUES (NULL, 'prompt-1', 0, '\(now)', '\(now)',
                        'sess-1', 1, 'p1', 'P1', '', '', '', '', 'draft', 'x');
                """)
        }
        return try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: "prompt-1",
            code: "gmcc", name: "GMCC overlay")).scope
    }

    private func assertNotRepoWritable(
        _ body: @autoclosure () throws -> Void,
        _ verb: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            try body()
            XCTFail("\(verb) accepted a SESSION_INSTANCE_ITEM scope", file: file, line: line)
        } catch let error as StoreError {
            guard case .dopeScopeNotRepoWritable(_, let scopeType, let named) = error else {
                return XCTFail("\(verb): wrong StoreError \(error)", file: file, line: line)
            }
            XCTAssertEqual(scopeType, DopeScopeType.sessionInstanceItem.rawValue,
                           file: file, line: line)
            XCTAssertEqual(named, verb, file: file, line: line)
        } catch {
            XCTFail("\(verb): unexpected error \(error)", file: file, line: line)
        }
    }

    func testWriteRepoRefusesOverlayScope() throws {
        let overlay = try makeOverlayScope()
        assertNotRepoWritable(
            _ = try self.store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: overlay.uuid)),
            "write-repo")
    }

    func testReadRepoRefusesOverlayScope() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        // The files exist and are perfectly readable — the refusal is about
        // the scope's tier, not about a missing tree.
        let overlay = try makeOverlayScope()
        assertNotRepoWritable(
            _ = try self.store.dopeReadRepo(DopeReadRepoRequest(scopeUuid: overlay.uuid)),
            "read-repo")
    }

    func testIngestRefusesOverlayScope() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let overlay = try makeOverlayScope()
        assertNotRepoWritable(
            _ = try self.store.dopeIngest(DopeIngestRequest(scopeUuid: overlay.uuid)),
            "ingest")
    }

    /// The gate must not cost the base tier anything.
    func testSessionBaseScopeStillPassesTheGate() throws {
        let scope = try makeScopeWithTree()
        XCTAssertNoThrow(
            try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid)))
        XCTAssertNoThrow(
            try store.dopeReadRepo(DopeReadRepoRequest(scopeUuid: scope.uuid)))
    }

    func testWriteReadIngestRoundTrip() throws {
        let scope = try makeScopeWithTree()
        XCTAssertEqual(scope.revision, 7)

        let written = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(written.revision, 7)
        XCTAssertTrue(written.filesWritten.contains(".gmcc/\(DopeDocumentCodec.scopeFileName)"))

        let read = try store.dopeReadRepo(DopeReadRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(read.onDiskRevision, 7)
        XCTAssertEqual(read.dbRevision, 7)
        XCTAssertEqual(read.drift, false)

        // Hand-bump the on-disk version to revision + 1 and ingest.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let bumped = DopeDocumentBundle(
            main: DopeScopeDocument(version: 8,
                                    scope: read.bundle.main.scope,
                                    persistence: read.bundle.main.persistence),
            domainFiles: read.bundle.domainFiles.map {
                DopePersistenceFileDocument(version: 8, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            })
        _ = try sandbox.writeAtomically(bumped)

        let treeBefore = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.scope.revision, 8)
        XCTAssertEqual(ingested.counts.properties, 3)

        // Content round-trips (identity churns — the locked consequence).
        let treeAfter = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        XCTAssertEqual(DopeProjection.documents(from: treeAfter).domainFiles.map(\.body),
                       DopeProjection.documents(from: treeBefore).domainFiles.map(\.body))
        XCTAssertEqual(treeAfter.domains[0].entities[0].properties.map(\.body),
                       treeBefore.domains[0].entities[0].properties.map(\.body))
        XCTAssertNotEqual(treeAfter.domains[0].identity.uuid,
                          treeBefore.domains[0].identity.uuid,
                          "ingest mints fresh rows")
    }

    func testIngestRevisionGateExactlyPlusOne() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))

        // On-disk version == db revision → refused (needs +1).
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.revisionConflict = $0 else {
                return XCTFail("wrong error: \($0)")
            }
        }
        // +2 → refused.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        func stamped(_ version: Int64) -> DopeDocumentBundle {
            DopeDocumentBundle(
                main: DopeScopeDocument(version: version,
                                    scope: read.main.scope,
                                    persistence: read.main.persistence),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: version, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                })
        }
        _ = try sandbox.writeAtomically(stamped(9))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid)))
        // Exactly +1 → accepted; the same file again → refused (stale).
        _ = try sandbox.writeAtomically(stamped(8))
        _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid)))
    }

    func testWriteRepoRefusesWhenFilesAreAheadUnlessForced() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))

        // Stamp the files ahead of the db.
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: 99,
                                    scope: read.main.scope,
                                    persistence: read.main.persistence),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: 99, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))

        XCTAssertThrowsError(
            try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.revisionConflict = $0 else {
                return XCTFail("wrong error: \($0)")
            }
        }
        let forced = try store.dopeWriteRepo(
            DopeWriteRepoRequest(scopeUuid: scope.uuid, force: true))
        XCTAssertEqual(forced.revision, 7)
        XCTAssertEqual(sandbox.peekRevision(), 7, "forced write re-stamps the db revision")
    }

    func testReadRepoWithExplicitDirPath() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let read = try store.dopeReadRepo(DopeReadRepoRequest(dirPath: repoRoot.path))
        XCTAssertEqual(read.onDiskRevision, 7)
        XCTAssertNil(read.dbRevision)
        XCTAssertNil(read.drift)
        XCTAssertThrowsError(try store.dopeReadRepo(DopeReadRepoRequest()))
        XCTAssertThrowsError(try store.dopeReadRepo(
            DopeReadRepoRequest(scopeUuid: scope.uuid, dirPath: repoRoot.path)))
    }

    /// Review fix [0]: enum refs are cross-domain-capable and domain files
    /// arrive alphabetically — a property in an EARLY domain referencing an
    /// enum in a LATE domain must survive the whole-tree insert.
    func testIngestWithCrossDomainEnumAndRelationshipRefs() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        // Late-sorting domain holds the enum + target property…
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_shared", name: "Shared")))
        let sharedEntity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "tag", name: "Tag")))
        let sharedId = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: sharedEntity.uuid,
            fields: DopeNodeFields(code: "id", name: "Id", dataType: .uuid, nullable: false)))
        let sharedEnum = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .enumeration, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "kind", name: "Kind")))
        // …and the early-sorting domain references both across.
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        let entity = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "kind", name: "Kind", dataType: .enumeration,
                                   enumUuid: sharedEnum.uuid)))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: entity.uuid,
            fields: DopeNodeFields(code: "tag", name: "Tag", dataType: .relationship,
                                   relationshipTargetUuid: sharedId.uuid)))

        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let next = read.main.version + 1
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: next,
                                    scope: read.main.scope,
                                    persistence: read.main.persistence),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: next, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.counts.domains, 2)

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        let user = core.entities.first { $0.body.code == "user" }!
        XCTAssertEqual(user.properties.first { $0.body.code == "kind" }?.body.enumRef,
                       "zzz_shared.enums.kind")
        XCTAssertEqual(user.properties.first { $0.body.code == "tag" }?.body.relationshipTargetRef,
                       "zzz_shared.tag.id")
    }

    /// Base refs are cross-domain-capable like enum refs: a composer in an
    /// EARLY domain referencing a base in a LATE-sorting domain must survive
    /// the whole-tree insert (pass-3 deferred resolution), and the ref must
    /// round-trip as the same dot-path.
    func testIngestWithCrossDomainBaseRef() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_base", name: "Base")))
        let base = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "base_entity", name: "Base Entity",
                                   entityType: .baseComposable)))
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User",
                                   baseComposableUuid: base.uuid)))

        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle
        let next = read.main.version + 1
        _ = try sandbox.writeAtomically(DopeDocumentBundle(
            main: DopeScopeDocument(version: next,
                                    scope: read.main.scope,
                                    persistence: read.main.persistence),
            domainFiles: read.domainFiles.map {
                DopePersistenceFileDocument(version: next, body: $0.body,
                                       entities: $0.entities, enums: $0.enums)
            }))
        let ingested = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(ingested.counts.entities, 2)

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        XCTAssertEqual(core.entities[0].body.baseComposableRef, "zzz_base.base_entity")
        // write-repo after ingest re-encodes the same dot-path.
        let written = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(written.revision, ingested.scope.revision)
        let reread = try sandbox.readBundle().bundle
        let coreFile = reread.domainFiles.first { $0.body.code == "aaa_core" }!
        XCTAssertEqual(coreFile.entities[0].body.baseComposableRef, "zzz_base.base_entity")
    }

    /// The repo pass in miniature: a cross-domain base, a materialized uuid
    /// tagged from it, and a relationship in a third entity targeting the
    /// MATERIALIZED property. Proves insertDopeTree's pass-5 deferred origin
    /// resolution and — via the second ingest — wipeDopeTree's base_origin
    /// NULL-out on a tree that already carries tags.
    func testIngestWithBaseOriginTags() throws {
        let scope = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", code: "gmcc", name: "GMCC")).scope
        let zzz = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "zzz_base", name: "Base")))
        let base = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: zzz.uuid,
            fields: DopeNodeFields(code: "base_entity", name: "Base Entity",
                                   entityType: .baseComposable)))
        let originUuidProp = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: base.uuid,
            fields: DopeNodeFields(code: "uuid", name: "Uuid", dataType: .uuid,
                                   nullable: false, isUnique: true)))
        let aaa = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .persistence, parentUuid: scope.uuid,
            fields: DopeNodeFields(code: "aaa_core", name: "Core")))
        let user = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "user", name: "User",
                                   baseComposableUuid: base.uuid)))
        let materialized = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: user.uuid,
            fields: DopeNodeFields(code: "uuid", name: "Uuid", dataType: .uuid,
                                   nullable: false, isUnique: true,
                                   baseOriginPropertyUuid: originUuidProp.uuid)))
        let post = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .entity, parentUuid: aaa.uuid,
            fields: DopeNodeFields(code: "post", name: "Post")))
        _ = try store.dopeNodeAdd(DopeNodeAddRequest(
            level: .property, parentUuid: post.uuid,
            fields: DopeNodeFields(code: "author", name: "Author", dataType: .relationship,
                                   relationshipTargetUuid: materialized.uuid)))

        func roundTripOnce() throws {
            _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
            let read = try sandbox.readBundle().bundle
            let next = read.main.version + 1
            _ = try sandbox.writeAtomically(DopeDocumentBundle(
                main: DopeScopeDocument(version: next,
                                    scope: read.main.scope,
                                    persistence: read.main.persistence),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: next, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                }))
            _ = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        }
        try roundTripOnce()
        // Second ingest wipes a tree that already carries base_origin tags —
        // the wipe-order regression.
        try roundTripOnce()

        let tree = try store.dopeGet(DopeGetRequest(sessionUuid: "sess-1")).tree
        let core = tree.domains.first { $0.body.code == "aaa_core" }!
        let userNode = core.entities.first { $0.body.code == "user" }!
        XCTAssertEqual(userNode.properties.first { $0.body.code == "uuid" }?.body.baseOriginRef,
                       "zzz_base.base_entity.uuid")
        let postNode = core.entities.first { $0.body.code == "post" }!
        XCTAssertEqual(postNode.properties.first { $0.body.code == "author" }?
                        .body.relationshipTargetRef,
                       "aaa_core.user.uuid",
                       "relationship must target the MATERIALIZED row, not the base's")
        try store.dbQueue.read { db in
            // The origin resolved to the base's actual row.
            let pair = try Row.fetchOne(db, sql: """
                SELECT p.uuid AS tagged, p.base_origin_property_uuid AS origin
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                WHERE e.code = 'user' AND p.code = 'uuid'
                """)
            let baseRow = try String.fetchOne(db, sql: """
                SELECT p.uuid FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                WHERE e.code = 'base_entity' AND p.code = 'uuid'
                """)
            XCTAssertEqual(pair?["origin"] as String?, baseRow)
        }
    }

    /// Review fixes [65] + [85]: ingest applies hand-edited scope
    /// name/description from main.doped.json, and bumps the scope row's
    /// optimistic-lock version ONLY when those fields actually changed.
    func testIngestScopeMetadataSemantics() throws {
        let scope = try makeScopeWithTree()
        _ = try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let read = try sandbox.readBundle().bundle

        func stamped(_ version: Int64, scopeBody: DopeScopeBody) -> DopeDocumentBundle {
            DopeDocumentBundle(
                main: DopeScopeDocument(version: version,
                                    scope: scopeBody,
                                    persistence: read.main.persistence),
                domainFiles: read.domainFiles.map {
                    DopePersistenceFileDocument(version: version, body: $0.body,
                                           entities: $0.entities, enums: $0.enums)
                })
        }

        // Pure tree ingest (metadata untouched): version stays.
        _ = try sandbox.writeAtomically(stamped(8, scopeBody: read.main.scope))
        let pure = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(pure.scope.version, scope.version,
                       "a pure tree ingest must not burn the scope's optimistic lock")

        // Hand-edited name: applied, version bumps by exactly 1.
        let edited = DopeScopeBody(code: read.main.scope.code, name: "GMCC Renamed",
                                   description: "hand-edited")
        _ = try sandbox.writeAtomically(stamped(9, scopeBody: edited))
        let renamed = try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))
        XCTAssertEqual(renamed.scope.name, "GMCC Renamed")
        XCTAssertEqual(renamed.scope.description, "hand-edited")
        XCTAssertEqual(renamed.scope.version, pure.scope.version + 1)

        // A changed scope CODE is identity, refused.
        let recoded = DopeScopeBody(code: "not_gmcc", name: "x", description: "")
        _ = try sandbox.writeAtomically(stamped(10, scopeBody: recoded))
        XCTAssertThrowsError(try store.dopeIngest(DopeIngestRequest(scopeUuid: scope.uuid))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("wrong error: \($0)")
            }
            XCTAssertTrue(detail.contains("identity"), detail)
        }
    }

    func testStaleInstanceRootFailsLoudly() throws {
        let scope = try makeScopeWithTree()
        try FileManager.default.removeItem(at: repoRoot)
        XCTAssertThrowsError(
            try store.dopeWriteRepo(DopeWriteRepoRequest(scopeUuid: scope.uuid))) { error in
            guard case StoreError.badRequest(let detail) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertTrue(detail.contains("missing or stale"), detail)
            XCTAssertTrue(detail.contains(self.repoRoot.path), detail)
        }
    }
}
