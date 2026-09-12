import XCTest
import GRDB
@testable import GMCCDaemonKit

/// m0010 is pure ADD. Like DopeSchemaTests, the assertions target the
/// SILENT failure modes: a column-list UNIQUE over the nullable owner FKs
/// would constrain nothing (NULLs are distinct), a missing tier CHECK would
/// let an owner chain go inconsistent forever, and a vertex FK aimed at
/// diagram_element instead of the subtype table would silently drop the
/// vertex-only-under-stroke/shape proof.
final class DiagramSchemaTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("m0010-\(UUID().uuidString).db").path
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
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');

                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');

                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func insertDiagram(
        _ db: Database, uuid: String, tier: String, project: String = "proj-1",
        instance: String? = nil, session: String? = nil, prompt: String? = nil,
        code: String, path: String? = nil
    ) throws {
        let now = Store.isoNow()
        try db.execute(sql: """
            INSERT INTO diagram (uuid, version, created_at, updated_at,
                project_uuid, session_uuid, prompt_uuid,
                tier, code, name, gmcc_diagram_path)
            VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [uuid, now, now, project, session, prompt,
                             tier, code, code, path])
        _ = instance
    }

    private func insertElement(
        _ db: Database, uuid: String, diagram: String, parent: String? = nil,
        type: String, code: String
    ) throws {
        let now = Store.isoNow()
        try db.execute(sql: """
            INSERT INTO diagram_element (uuid, version, created_at, updated_at,
                diagram_uuid, parent_element_uuid, element_type, code, name)
            VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [uuid, now, now, diagram, parent, type, code, code])
    }

    // MARK: - Tier chain CHECKs

    func testTierChainChecksRejectInconsistentOwnerChains() throws {
        try store.dbQueue.write { db in
            // PROJECT tier carrying a session — refused.
            XCTAssertThrowsError(try self.insertDiagram(
                db, uuid: "d-bad-2", tier: "PROJECT",
                session: "sess-1", code: "b"))
            // PROMPT tier missing the prompt FK — refused.
            XCTAssertThrowsError(try self.insertDiagram(
                db, uuid: "d-bad-3", tier: "PROMPT",
                session: "sess-1", code: "c"))
            // SESSION tier missing the session FK — refused.
            XCTAssertThrowsError(try self.insertDiagram(
                db, uuid: "d-bad-4", tier: "SESSION", code: "d"))
            // The three legal shapes all insert.
            try self.insertDiagram(db, uuid: "d-p", tier: "PROJECT", code: "p")
            try self.insertDiagram(db, uuid: "d-s", tier: "SESSION",
                                   session: "sess-1", code: "s")
            try self.insertDiagram(db, uuid: "d-pr", tier: "PROMPT",
                                   session: "sess-1", prompt: "prompt-a", code: "pr")
        }
    }

    /// m0021 removed the INSTANCE tier outright — it existed only to give a
    /// diagram a repo checkout to anchor a path against, and CKFS storage
    /// gives every remaining tier a root.
    func testInstanceTierIsNoLongerAcceptedBySchema() throws {
        try store.dbQueue.write { db in
            XCTAssertThrowsError(try self.insertDiagram(
                db, uuid: "d-inst", tier: "INSTANCE", code: "i"),
                "INSTANCE must fail the tier CHECK")
        }
    }

    /// INVERTED BY m0021, deliberately. This test previously asserted the
    /// opposite — that a path at PROJECT tier was refused — because only an
    /// instance carried a filesystem checkout. Screenshots now materialize
    /// under CKFS storage, which a project has as much as a session does, so
    /// the CHECK was dropped and a path is legal at every tier.
    func testGmccDiagramPathIsLegalAtEveryTier() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-proj", tier: "PROJECT",
                                   code: "a", path: "docs/d.png")
            try self.insertDiagram(db, uuid: "d-sess", tier: "SESSION",
                                   session: "sess-1", code: "b", path: "docs/e.png")
            try self.insertDiagram(db, uuid: "d-prompt", tier: "PROMPT",
                                   session: "sess-1", prompt: "prompt-a",
                                   code: "c", path: "docs/f.png")
        }
    }

    // MARK: - Partial unique indexes (the NULLs-are-distinct trap, proven)

    func testPerTierCodeUniquenessActuallyRejects() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            XCTAssertThrowsError(try self.insertDiagram(
                db, uuid: "d-2", tier: "SESSION",
                session: "sess-1", code: "main"))
            // Same code at ANOTHER tier is legal (per-tier namespaces).
            try self.insertDiagram(db, uuid: "d-3", tier: "PROMPT",
                                   session: "sess-1", prompt: "prompt-a", code: "main")
        }
    }

    // MARK: - Element CHECKs

    /// INVERTED BY m0021, deliberately — read the reasoning before treating
    /// this as a regression.
    ///
    /// This used to assert that a literal-list CHECK coupled element_type to
    /// parent-nullability. Both literal-list CHECKs were dropped: validity
    /// is DiagramElementTypeSpec's, enforced by both write paths and thrown
    /// on at read. The schema deliberately no longer knows the vocabulary,
    /// which is exactly what makes an eighth element type a registry entry
    /// instead of a table rebuild (DopeCogElement.swift:11-19).
    ///
    /// So: a raw INSERT bypassing both write paths is now ACCEPTED by SQLite,
    /// and the registry is what refuses it. Both halves are asserted here —
    /// the schema's new permissiveness, and the registry's rule that replaced
    /// it — because "the db stopped enforcing this" is only safe if something
    /// else demonstrably still does.
    func testTopLevelnessIsEnforcedByTheRegistryNotTheSchema() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            try self.insertElement(db, uuid: "e-layer", diagram: "d-1",
                                   type: "drawing_layer", code: "layer_0001")
            // The schema no longer objects to either shape.
            try self.insertElement(db, uuid: "e-raw-stroke", diagram: "d-1",
                                   type: "drawing_stroke", code: "s_raw")
            try self.insertElement(db, uuid: "e-raw-layer", diagram: "d-1",
                                   parent: "e-layer", type: "drawing_layer", code: "l_raw")
        }

        // The registry does. A top-level type has no allowedParentTypes; a
        // child type names the parents it may live under.
        XCTAssertNil(DiagramElementTypeSpec.spec(for: .drawingLayer).allowedParentTypes,
                     "drawing_layer is top-level: nil means parent must be NULL")
        XCTAssertEqual(DiagramElementTypeSpec.spec(for: .drawingStroke).allowedParentTypes,
                       [.drawingLayer])
        XCTAssertNil(
            DiagramElementTypeSpec.spec(for: .dopeScopePersistenceLayer).allowedParentTypes)
    }

    /// The positive proof of the whole move: adding an element type is a
    /// registry entry and a subtype table, never a migration. If this ever
    /// fails, the schema has grown an opinion about the vocabulary again.
    func testAddingAnElementTypeNeedsNoSchemaChange() throws {
        let sql = try store.dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT sql FROM sqlite_master
                 WHERE type = 'table' AND name = 'diagram_element'
                """) ?? ""
        }
        XCTAssertFalse(sql.contains("element_type IN"),
                       "diagram_element must carry NO element_type CHECK: \(sql)")
        XCTAssertFalse(sql.contains("parent_element_uuid IS NULL)"),
                       "the parent-nullability coupling must be gone too: \(sql)")
        // The one structural guard that is NOT vocabulary stays.
        XCTAssertTrue(sql.contains("parent_element_uuid != uuid"),
                      "self-parenting must still be refused by the schema")
        // Every registered type has a distinct subtype table to land in.
        let tables = Set(DiagramElementType.allCases.map {
            DiagramElementTypeSpec.spec(for: $0).subtypeTable
        })
        XCTAssertEqual(tables.count, DiagramElementType.allCases.count,
                       "one type, one subtype table")
    }

    func testElementCodeIsDiagramWideUnique() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            try self.insertElement(db, uuid: "e-1", diagram: "d-1",
                                   type: "drawing_layer", code: "x")
            XCTAssertThrowsError(try self.insertElement(
                db, uuid: "e-2", diagram: "d-1", type: "dope_scope_persistence_layer", code: "x"))
        }
    }

    // MARK: - Vertex anchoring + CASCADE chain

    func testVertexFkTargetsSubtypeTableNotElement() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            try self.insertElement(db, uuid: "e-scope", diagram: "d-1",
                                   type: "dope_scope_persistence_layer", code: "sc")
            let now = Store.isoNow()
            // A vertex pointed at an element with NO stroke subtype row must
            // be refused by the FK — the schema itself proves
            // vertex-only-under-stroke.
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO diagram_stroke_vertex (uuid, version, created_at, updated_at,
                    stroke_element_uuid, seq, x, y)
                VALUES ('v-bad', 0, '\(now)', '\(now)', 'e-scope', 0, 1, 2)
                """))
        }
    }

    func testElementDeleteCascadesSubtypeAndVertices() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            try self.insertElement(db, uuid: "e-layer", diagram: "d-1",
                                   type: "drawing_layer", code: "l1")
            try self.insertElement(db, uuid: "e-stroke", diagram: "d-1",
                                   parent: "e-layer", type: "drawing_stroke", code: "s1")
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO diagram_drawing_layer (uuid, version, created_at, updated_at, element_uuid)
                VALUES ('sub-l', 0, '\(now)', '\(now)', 'e-layer');
                INSERT INTO diagram_drawing_stroke (uuid, version, created_at, updated_at, element_uuid)
                VALUES ('sub-s', 0, '\(now)', '\(now)', 'e-stroke');
                INSERT INTO diagram_stroke_vertex (uuid, version, created_at, updated_at,
                    stroke_element_uuid, seq, x, y)
                VALUES ('v-1', 0, '\(now)', '\(now)', 'e-stroke', 0, 1, 2);
                """)
            // Deleting the LAYER cascades: child element → stroke subtype →
            // vertex, three hops of pure CASCADE, no RESTRICT anywhere.
            try db.execute(sql: "DELETE FROM diagram_element WHERE uuid = 'e-layer'")
            for table in ["diagram_element", "diagram_drawing_layer",
                          "diagram_drawing_stroke", "diagram_stroke_vertex"] {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
                XCTAssertEqual(count, 0, "\(table) should be empty after the cascade")
            }
        }
    }

    func testVertexSeqUniquePerOwner() throws {
        try store.dbQueue.write { db in
            try self.insertDiagram(db, uuid: "d-1", tier: "SESSION",
                                   session: "sess-1", code: "main")
            try self.insertElement(db, uuid: "e-layer", diagram: "d-1",
                                   type: "drawing_layer", code: "l1")
            try self.insertElement(db, uuid: "e-stroke", diagram: "d-1",
                                   parent: "e-layer", type: "drawing_stroke", code: "s1")
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO diagram_drawing_stroke (uuid, version, created_at, updated_at, element_uuid)
                VALUES ('sub-s', 0, '\(now)', '\(now)', 'e-stroke');
                INSERT INTO diagram_stroke_vertex (uuid, version, created_at, updated_at,
                    stroke_element_uuid, seq, x, y)
                VALUES ('v-1', 0, '\(now)', '\(now)', 'e-stroke', 0, 1, 2);
                """)
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO diagram_stroke_vertex (uuid, version, created_at, updated_at,
                    stroke_element_uuid, seq, x, y)
                VALUES ('v-2', 0, '\(now)', '\(now)', 'e-stroke', 0, 3, 4)
                """))
        }
    }

    /// The ledger head. Renamed off "IsTen" so it stops lying every time a
    /// migration lands; it asserts that the applied ledger and the compiled
    /// constant AGREE, which is the property that actually matters, and
    /// pins the current value so a migration can never land silently.
    func testSchemaVersionMatchesCompiledConstant() throws {
        XCTAssertEqual(try store.schemaVersion(), Migrations.currentSchemaVersion)
        XCTAssertEqual(Migrations.currentSchemaVersion, 26)
    }
}
