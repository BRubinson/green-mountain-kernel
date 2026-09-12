import GRDB
import XCTest
@testable import GMCCDaemonKit

/// COGS — the registry-governed element family.
final class DopeCogTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var scopeUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-cog-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String { "NULL, '\(uuid)', 0, '\(now)', '\(now)'" }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path,
                    ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/r', 'x');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                """)
        }
        scopeUuid = try store.dopeInit(DopeInitRequest(
            sessionUuid: "sess-1", promptUuid: nil, code: "gmcc", name: "GMCC")).scope.uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @discardableResult
    private func addCog(_ code: String = "systems") throws -> DopeCogResponse {
        try store.dopeCogAdd(DopeCogAddRequest(
            scopeUuid: scopeUuid, code: code, name: code.capitalized))
    }

    func testAddCogAndSeedTheThreePrimarySystems() throws {
        let cog = try addCog()
        for (code, path) in [("gm_vibes", "gmvibes/"),
                             ("gm_bot", "plugins/gmcc/skills/"),
                             ("gm_daemon", "plugins/gmcc/daemon/")] {
            _ = try store.dopeCogElementAdd(DopeCogElementAddRequest(
                cogUuid: cog.cog.uuid, elementType: "Hull",
                code: code, name: code, primaryPath: path))
        }
        let got = try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid))
        XCTAssertEqual(got.cogs.count, 1)
        XCTAssertEqual(got.cogs[0].elements.count, 3)
        // Ordered by (sort_order, code) — all three share sort_order 0.
        XCTAssertEqual(got.cogs[0].elements.map { $0.code },
                       ["gm_bot", "gm_daemon", "gm_vibes"])
        XCTAssertEqual(Set(got.cogs[0].elements.compactMap { $0.primaryPath }),
                       ["gmvibes/", "plugins/gmcc/skills/", "plugins/gmcc/daemon/"])
    }

    func testSeededSystemsCarryTheirPaths() throws {
        let cog = try addCog()
        _ = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "gm_daemon", name: "GM Daemon", primaryPath: "plugins/gmcc/daemon/"))
        let got = try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid))
        XCTAssertEqual(got.cogs[0].elements[0].primaryPath, "plugins/gmcc/daemon/")
        XCTAssertEqual(got.cogs[0].elements[0].elementType, "Hull")
    }

    // MARK: - file round-trip

    /// THE guard against permanent phantom conflicts. The collapse to
    /// links.persistence_owners drops each owner's own name/description, so
    /// expansion has to synthesize them — and if the seeder and the reader
    /// ever synthesize differently, every publish/ingest cycle yields a
    /// different tree, the merge baseline never matches disk, and boot
    /// reports conflicts on cogs nobody touched. Assert the fixed point.
    func testCogCollapseExpandIsAFixedPoint() throws {
        let cog = try addCog("gm_daemon")
        let hull = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "gm_daemon", name: "GM Daemon", primaryPath: "plugins/gmcc/daemon"))
        for (i, domain) in ["agentics", "doped"].enumerated() {
            let child = DopeCogProjection.ownerElement(
                parentCode: "gm_daemon", persistenceCode: domain, sortOrder: i)
            _ = try store.dopeCogElementAdd(DopeCogElementAddRequest(
                cogUuid: cog.cog.uuid, elementType: "PersistenceOwner",
                code: child.code, name: child.name, description: child.description,
                sortOrder: child.sortOrder,
                parentElementUuid: hull.element.uuid, dopePersistenceCode: domain))
        }

        let before = try store.dbQueue.read { db in
            try self.store.fetchDopeCogs(db, scopeUuid: self.scopeUuid)
        }
        let doc = DopeCogProjection.document(from: before[0])
        XCTAssertEqual(doc.elements.count, 1, "owners must collapse into the hull")
        XCTAssertEqual(doc.elements[0].links?.persistenceOwners, ["agentics", "doped"])

        // Expand back through the real ingest path and re-collapse.
        try store.dbQueue.write { db in
            try self.store.wipeDopeTree(db, scopeUuid: self.scopeUuid)
            try self.store.insertDopeCogs(
                db, scopeUuid: self.scopeUuid, cogFiles: [doc])
        }
        let after = try store.dbQueue.read { db in
            try self.store.fetchDopeCogs(db, scopeUuid: self.scopeUuid)
        }
        XCTAssertEqual(DopeCogProjection.document(from: after[0]), doc,
                       "expand(collapse(x)) must equal collapse(x) — otherwise every "
                     + "publish/ingest cycle drifts and the merge reports phantom conflicts")
    }

    // MARK: - PersistenceOwner

    /// One PersistenceOwner element per owned domain, parented to a Hull.
    /// Multiplicity is sibling elements rather than a many-valued field,
    /// which is what lets the registry keep its
    /// one-type-one-subtype-table shape.
    func testHullOwnsPersistenceDomainsViaSiblingElements() throws {
        let cog = try addCog()
        let hull = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "gm_daemon", name: "GM Daemon", primaryPath: "plugins/gmcc/daemon/"))

        for domain in ["doped", "agentics"] {
            _ = try store.dopeCogElementAdd(DopeCogElementAddRequest(
                cogUuid: cog.cog.uuid, elementType: "PersistenceOwner",
                code: "owns_\(domain)", name: "Owns \(domain)",
                parentElementUuid: hull.element.uuid,
                dopePersistenceCode: domain))
        }

        let got = try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid))
        let owners = got.cogs[0].elements.filter { $0.elementType == "PersistenceOwner" }
        XCTAssertEqual(owners.count, 2)
        XCTAssertEqual(Set(owners.compactMap { $0.dopePersistenceCode }), ["doped", "agentics"])
    }

    /// Links may live on a Hull and nowhere else.
    func testPersistenceOwnerRefusesTopLevelAndNonHullParents() throws {
        let cog = try addCog()

        // Top level: refused, because allowedParentTypes is [.hull].
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "PersistenceOwner",
            code: "orphan", name: "Orphan", dopePersistenceCode: "doped")))

        // Parented under another PersistenceOwner: also refused.
        let hull = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "gm_daemon", name: "GM Daemon", primaryPath: "plugins/gmcc/daemon/"))
        let owner = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "PersistenceOwner",
            code: "owns_doped", name: "Owns doped",
            parentElementUuid: hull.element.uuid, dopePersistenceCode: "doped"))
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "PersistenceOwner",
            code: "nested", name: "Nested",
            parentElementUuid: owner.element.uuid, dopePersistenceCode: "agentics")))
    }

    /// Required fields are per-type now. The old code checked primary_path
    /// literally, which a PersistenceOwner — which has no primary_path at
    /// all — could never satisfy.
    func testRequiredFieldsAreValidatedPerType() throws {
        let cog = try addCog()
        // Hull without --primary-path.
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull", code: "h", name: "H")))
        let hull = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "gm_daemon", name: "GM Daemon", primaryPath: "plugins/gmcc/daemon/"))
        // PersistenceOwner without --dope-persistence-code.
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "PersistenceOwner", code: "o", name: "O",
            parentElementUuid: hull.element.uuid)))
        // A PersistenceOwner does NOT need a primary_path.
        XCTAssertNoThrow(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "PersistenceOwner", code: "o", name: "O",
            parentElementUuid: hull.element.uuid, dopePersistenceCode: "doped")))
    }

    /// The registry IS the constraint, because the column deliberately has no
    /// CHECK. An unknown type must still be refused.
    func testUnknownElementTypeIsRefusedByTheRegistry() throws {
        let cog = try addCog()
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Not_A_Type",
            code: "x", name: "x", primaryPath: "p/")))
    }

    /// The reason the column carries no CHECK: adding a type must never be a
    /// migration. Proven structurally — the schema accepts a value the Swift
    /// registry does not yet know, so shipping a new type is additive code.
    func testANewElementTypeWouldNeedNoMigration() throws {
        let cog = try addCog()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            // A future type, inserted directly. If element_type carried a
            // CHECK this would fail and adding a type would mean a rebuild.
            try db.execute(sql: """
                INSERT INTO dope_cog_element (id, uuid, version, created_at, updated_at,
                    dope_cog_uuid, element_type, code, name)
                VALUES (NULL, 'future-1', 0, ?, ?, ?, 'Future_Type', 'f', 'F')
                """, arguments: [now, now, cog.cog.uuid])
        }
        // And the registry still refuses to HYDRATE it, so a bad value is
        // caught loudly at read rather than rendering as something plausible.
        XCTAssertThrowsError(try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid)))
    }

    func testPrimarySystemRequiresAPath() throws {
        let cog = try addCog()
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull", code: "x", name: "x")))
    }

    func testPrimarySystemIsTopLevelOnly() throws {
        let cog = try addCog()
        let parent = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "a", name: "A", primaryPath: "a/"))
        XCTAssertThrowsError(try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull", code: "b", name: "B",
            parentElementUuid: parent.element.uuid, primaryPath: "b/")))
    }

    /// The dope scope binding is a ghost-tolerant code, never an FK — a
    /// dangling value is a legal renderable state, exactly like a diagram's.
    func testDanglingDopeScopeCodeIsLegal() throws {
        let cog = try addCog()
        let e = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull", code: "a", name: "A",
            dopeScopeCode: "no_such_scope", primaryPath: "a/"))
        XCTAssertEqual(e.element.dopeScopeCode, "no_such_scope")
        let got = try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid))
        XCTAssertEqual(got.cogs[0].elements[0].dopeScopeCode, "no_such_scope")
    }

    func testCogMutationsBumpTheScopeRevision() throws {
        let before = try store.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT revision FROM dope_scope WHERE uuid = ?",
                               arguments: [self.scopeUuid!])!
        }
        let cog = try addCog()
        XCTAssertGreaterThan(cog.revision, before)
    }

    func testCogCodeUniquenessIsPartialOnTombstones() throws {
        _ = try addCog("systems")
        XCTAssertThrowsError(try addCog("systems"), "two live cogs may not share a code")
    }

    func testDeleteCascadesElements() throws {
        let cog = try addCog()
        _ = try store.dopeCogElementAdd(DopeCogElementAddRequest(
            cogUuid: cog.cog.uuid, elementType: "Hull",
            code: "a", name: "A", primaryPath: "a/"))
        let r = try store.dopeCogDelete(DopeCogDeleteRequest(
            uuid: cog.cog.uuid, expectedVersion: cog.cog.version))
        XCTAssertEqual(r.cascadedElements, 1)
        XCTAssertTrue(try store.dopeCogGet(DopeCogGetRequest(scopeUuid: scopeUuid)).cogs.isEmpty)
    }

    /// Same rule as the persistence tree: a tombstone is masking state, so a
    /// base scope refuses it.
    func testSoftDeleteIsRefusedInABaseScope() throws {
        let cog = try addCog()
        XCTAssertThrowsError(try store.dopeCogDelete(DopeCogDeleteRequest(
            uuid: cog.cog.uuid, expectedVersion: cog.cog.version, soft: true)))
    }
}
