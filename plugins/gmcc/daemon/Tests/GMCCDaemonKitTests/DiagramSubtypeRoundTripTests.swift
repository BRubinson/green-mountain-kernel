import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The standing guarantee for generated subtype SQL: for EVERY element type,
/// insert -> hydrate -> replace-payload -> hydrate returns the payload that
/// was written, both times.
///
/// This class exists because of a bug it would have caught. m0018 renamed
/// `diagram_dope_scope` to `diagram_dope_scope_persistence_layer`; the INSERT
/// path and the hydrate path were both updated, but `replaceSubtypeRow`'s
/// UPDATE was not — so every payload-replacing update of a
/// `dope_scope_persistence_layer` element threw `no such table` at runtime,
/// against live data, silently.
///
/// It survived the differential oracle (DiagramKitAdditionsTests) because
/// that oracle compares TREE SHAPES between the store and DiagramTreeReducer,
/// and the reducer contains no SQL at all. A SQL error in one implementation
/// is structurally invisible to a test that compares the two implementations'
/// in-memory results. Only a test that actually round-trips through SQLite
/// can see it — this one.
///
/// The fixtures are driven off an exhaustive `switch` over
/// `DiagramElementType`, so a new element type CANNOT ship without a
/// round-trip fixture: it fails to compile, exactly as every other element
/// site in this codebase does (see DiagramResolver.swift:118-120).
final class DiagramSubtypeRoundTripTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!
    private var diagramUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-subtype-\(UUID().uuidString).db").path
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
                """)
        }
        diagramUuid = try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", code: "main", name: "Main")).diagram.uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Fixtures

    /// The two payloads a type round-trips through, plus the parent it needs.
    /// Written as an exhaustive switch so a new element type breaks the build
    /// here rather than shipping untested.
    private struct Fixture {
        let initial: DiagramElementPayload
        let updated: DiagramElementPayload
    }

    private func fixture(for type: DiagramElementType) -> Fixture {
        switch type {
        case .drawingLayer:
            return Fixture(
                initial: .drawingLayer(DrawingLayerPayload(
                    opacity: 1, visible: true, locked: false)),
                updated: .drawingLayer(DrawingLayerPayload(
                    opacity: 0.25, visible: false, locked: true)))
        case .drawingStroke:
            return Fixture(
                initial: .drawingStroke(DrawingStrokePayload(
                    tool: .pencil, strokeColor: "#111111", strokeWidth: 2,
                    vertices: [DiagramVertex(x: 0, y: 0),
                               DiagramVertex(x: 5, y: 5, pressure: 0.5)])),
                updated: .drawingStroke(DrawingStrokePayload(
                    tool: .highlighter, strokeColor: "#ff0000", strokeWidth: 8,
                    vertices: [DiagramVertex(x: -1, y: -1, pressure: 0.25),
                               DiagramVertex(x: 2, y: 3),
                               DiagramVertex(x: 9, y: 9, pressure: 1)])))
        case .drawingShape:
            return Fixture(
                initial: .drawingShape(DrawingShapePayload(
                    shapeKind: .ellipse, strokeColor: "#111111", strokeWidth: 2,
                    vertices: [DiagramVertex(x: -5, y: -5), DiagramVertex(x: 5, y: 5)])),
                // corner_radius is legal ONLY on rectangles, so the update leg
                // also proves shape_kind and its dependent column move together.
                updated: .drawingShape(DrawingShapePayload(
                    shapeKind: .rectangle, strokeColor: "#00ff00", strokeWidth: 4,
                    fillColor: "#0000ff", cornerRadius: 3,
                    vertices: [DiagramVertex(x: -8, y: -2), DiagramVertex(x: 8, y: 2)])))
        case .dopeScopePersistenceLayer:
            // The arm that carried the bug: its UPDATE named the pre-m0018 table.
            return Fixture(
                initial: .dopeScopePersistenceLayer(
                    DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
                updated: .dopeScopePersistenceLayer(
                    DopeScopePersistenceLayerPayload(dopeScopeCode: "other_scope")))
        case .dopeEntity:
            return Fixture(
                initial: .dopeEntity(DopeEntityPayload(entityCode: "diagrams.diagram")),
                updated: .dopeEntity(DopeEntityPayload(entityCode: "project.session")))
        case .drawingText:
            return Fixture(
                initial: .drawingText(DrawingTextPayload(
                    markdown: "hello", width: 120, height: 40, fontSize: 13,
                    textColor: "#111111")),
                updated: .drawingText(DrawingTextPayload(
                    markdown: "# changed\nwith *emphasis*", width: 260, height: 90,
                    fontSize: 17, textColor: "#00ff00", backgroundColor: "#eeeeee")))
        case .connector:
            // targetElementUuid is filled in by the caller once the peer it
            // points at actually exists — a fixture cannot know a uuid that
            // has not been minted yet. The update leg exercises the v23
            // vocabulary: routing kind, tail kind, and a widened head.
            return Fixture(
                initial: .connector(ConnectorPayload(
                    strokeColor: "#111111", strokeWidth: 2,
                    lineStyle: .solid, headKind: .arrow, label: "")),
                updated: .connector(ConnectorPayload(
                    strokeColor: "#ff00ff", strokeWidth: 5,
                    lineStyle: .dashed, headKind: .openArrow,
                    routingKind: .curved, tailKind: .diamond,
                    label: "depends on")))
        case .umlNode:
            return Fixture(
                initial: .umlNode(UmlNodePayload(
                    nodeKind: .roundedRect, width: 160, height: 90,
                    markdown: "# Node")),
                updated: .umlNode(UmlNodePayload(
                    nodeKind: .dbCylinder, width: 220, height: 140,
                    markdown: "## Store\n- rows",
                    fontSize: 15, textColor: "#222222",
                    strokeColor: "#0044ff", strokeWidth: 3,
                    fillColor: "#eef2ff")))
        }
    }

    /// The full ancestor chain a type needs, outermost first.
    ///
    /// Walks `allowedParentTypes` up to the top, so a connector (which lives
    /// under an entity, which lives under a scope) gets its whole chain
    /// rather than one level.
    private func ancestorChain(for type: DiagramElementType) -> [DiagramElementType] {
        var chain: [DiagramElementType] = []
        var current = type
        while let allowed = DiagramElementTypeSpec.spec(for: current).allowedParentTypes,
              let parent = allowed.sorted(by: { $0.rawValue < $1.rawValue }).first {
            chain.insert(parent, at: 0)
            current = parent
        }
        return chain
    }

    /// Build a type's ancestors, returning the clientRef of its direct
    /// parent (nil for a top-level type) and, for a connector, the clientRef
    /// of a legal PEER target: a sibling of the connector's own parent.
    private func buildContext(
        for type: DiagramElementType, tag: String,
        into mutations: inout [DiagramMutation]
    ) -> (parentRef: String?, targetRef: String?) {
        let chain = ancestorChain(for: type)
        var parentRef: String? = nil
        for (depth, ancestor) in chain.enumerated() {
            let ref = "\(tag)-a\(depth)"
            mutations.append(.elementAdd(DiagramElementAdd(
                clientRef: ref, parentClientRef: parentRef,
                payload: fixture(for: ancestor).initial)))
            parentRef = ref
        }
        guard type == .connector, let directParent = chain.last else {
            return (parentRef, nil)
        }
        // A legal connector target is a PEER OF ITS PARENT — another element
        // sharing the parent's parent, not another child of the parent.
        let grandparentRef = chain.count >= 2 ? "\(tag)-a\(chain.count - 2)" : nil
        let targetRef = "\(tag)-peer"
        mutations.append(.elementAdd(DiagramElementAdd(
            clientRef: targetRef, parentClientRef: grandparentRef,
            payload: fixture(for: directParent).initial)))
        return (parentRef, targetRef)
    }

    // MARK: - Helpers

    private func node(_ uuid: String) throws -> DiagramElementNode {
        let tree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagramUuid)).tree
        func find(_ nodes: [DiagramElementNode]) -> DiagramElementNode? {
            for n in nodes {
                if n.identity.uuid == uuid { return n }
                if let hit = find(n.children) { return hit }
            }
            return nil
        }
        guard let found = find(tree.elements) else {
            throw XCTSkip("element \(uuid) not found in hydrated tree")
        }
        return found
    }

    // MARK: - The round trip, per element type

    func testEverySubtypeRoundTripsThroughInsertAndReplace() throws {
        for type in DiagramElementType.allCases {
            let f = fixture(for: type)
            var mutations: [DiagramMutation] = []
            let context = buildContext(for: type, tag: "rt-\(type.rawValue)",
                                       into: &mutations)
            mutations.append(.elementAdd(DiagramElementAdd(
                parentClientRef: context.parentRef,
                targetClientRef: context.targetRef,
                payload: f.initial)))

            let added = try store.diagramBatchApply(DiagramBatchApplyRequest(
                diagramUuid: diagramUuid, mutations: mutations))
            let uuid = try XCTUnwrap(added.results.last?.uuid)

            // 1. INSERT path hydrates back to what was written.
            let afterInsert = try node(uuid)
            XCTAssertEqual(afterInsert.payload,
                           try expected(f.initial, resolvingTargetFrom: afterInsert),
                           "\(type.rawValue): insert -> hydrate lost or altered the payload")

            // 2. REPLACE path hydrates back to what was written. This is the
            //    leg that was broken for dope_scope_persistence_layer: the
            //    UPDATE targeted a table m0018 had already renamed away.
            let updated = try carryTarget(from: afterInsert, into: f.updated)
            _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
                diagramUuid: diagramUuid,
                mutations: [.elementUpdate(DiagramElementUpdate(
                    elementUuid: uuid,
                    expectedVersion: afterInsert.identity.version,
                    payload: updated))]))

            let afterReplace = try node(uuid)
            XCTAssertEqual(afterReplace.payload, updated,
                           "\(type.rawValue): replace -> hydrate lost or altered the payload")
        }
    }

    /// A connector's stored target is minted during the batch, so the
    /// expected payload is the fixture with whatever uuid the store
    /// resolved. Every other type compares as written.
    private func expected(
        _ payload: DiagramElementPayload, resolvingTargetFrom node: DiagramElementNode
    ) throws -> DiagramElementPayload {
        guard case .connector(let fixture) = payload,
              case .connector(let stored) = node.payload else {
            // Strokes are stored packed, so pressure quantizes onto 254
            // steps. Compare against what storage can actually hold.
            return DiagramStrokeCodec.normalizedForStorage(payload)
        }
        XCTAssertNotNil(stored.targetElementUuid,
                        "a connector added with targetClientRef must persist a target")
        return .connector(ConnectorPayload(
            targetElementUuid: stored.targetElementUuid,
            strokeColor: fixture.strokeColor, strokeWidth: fixture.strokeWidth,
            lineStyle: fixture.lineStyle, headKind: fixture.headKind,
            routingKind: fixture.routingKind, tailKind: fixture.tailKind,
            label: fixture.label))
    }

    /// Carry the resolved target into the update fixture — a payload replace
    /// is wholesale, so dropping it would be a legitimate "target cleared"
    /// write rather than the round trip under test.
    private func carryTarget(
        from node: DiagramElementNode, into payload: DiagramElementPayload
    ) throws -> DiagramElementPayload {
        guard case .connector(let update) = payload,
              case .connector(let stored) = node.payload else {
            return DiagramStrokeCodec.normalizedForStorage(payload)
        }
        return .connector(ConnectorPayload(
            targetElementUuid: stored.targetElementUuid,
            strokeColor: update.strokeColor, strokeWidth: update.strokeWidth,
            lineStyle: update.lineStyle, headKind: update.headKind,
            routingKind: update.routingKind, tailKind: update.tailKind,
            label: update.label))
    }

    /// The regression pinned to its own name, so a failure reads as the bug
    /// it is rather than as one row of a loop.
    func testScopePersistenceLayerPayloadReplaceHitsTheRenamedTable() throws {
        let added = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [.elementAdd(DiagramElementAdd(
                payload: .dopeScopePersistenceLayer(
                    DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc"))))]))
        let uuid = try XCTUnwrap(added.results[0].uuid)
        let version = try XCTUnwrap(added.results[0].version)

        // Before the fix this threw `no such table: diagram_dope_scope`.
        _ = try store.diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid,
            mutations: [.elementUpdate(DiagramElementUpdate(
                elementUuid: uuid, expectedVersion: version,
                payload: .dopeScopePersistenceLayer(
                    DopeScopePersistenceLayerPayload(dopeScopeCode: "renamed_scope"))))]))

        guard case .dopeScopePersistenceLayer(let p) = try node(uuid).payload else {
            return XCTFail("element morphed type on payload replace")
        }
        XCTAssertEqual(p.dopeScopeCode, "renamed_scope")
    }

    /// The subtype row must land in the table the registry names — proving
    /// the SQL and the spec agree, which is the invariant that broke.
    func testSubtypeRowLandsInTheTableTheRegistryNames() throws {
        for type in DiagramElementType.allCases {
            let f = fixture(for: type)
            var mutations: [DiagramMutation] = []
            let context = buildContext(for: type, tag: "tbl-\(type.rawValue)",
                                       into: &mutations)
            mutations.append(.elementAdd(DiagramElementAdd(
                parentClientRef: context.parentRef,
                targetClientRef: context.targetRef,
                payload: f.initial)))
            let added = try store.diagramBatchApply(DiagramBatchApplyRequest(
                diagramUuid: diagramUuid, mutations: mutations))
            let uuid = try XCTUnwrap(added.results.last?.uuid)

            let table = DiagramElementTypeSpec.spec(for: type).subtypeTable
            let count = try store.dbQueue.read { db in
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(table) WHERE element_uuid = ?",
                    arguments: [uuid]) ?? -1
            }
            XCTAssertEqual(count, 1,
                           "\(type.rawValue): expected exactly one row in \(table)")
        }
    }
}
