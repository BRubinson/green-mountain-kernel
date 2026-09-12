import XCTest
import GRDB
@testable import GMCCDaemonKit

/// Verb-machine tests for the DIAGRAM family: init derivation + idempotence,
/// list-no-union, get addressing + the three-way absence discrimination,
/// containment validation, code auto-minting, hydration round-trips, and the
/// payload/mutation wire codecs.
final class DiagramMachineTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagram-machine-\(UUID().uuidString).db").path
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

    // MARK: - Helpers

    @discardableResult
    private func initDiagram(code: String = "main",
                             sessionUuid: String? = "sess-1",
                             promptUuid: String? = nil,
                             projectUuid: String? = nil,
                             instanceUuid: String? = nil) throws -> DiagramResponse {
        try store.diagramInit(DiagramInitRequest(
            projectUuid: projectUuid, instanceUuid: instanceUuid,
            sessionUuid: sessionUuid, promptUuid: promptUuid,
            code: code, name: "Main"))
    }

    @discardableResult
    private func addElement(
        _ diagramUuid: String, payload: DiagramElementPayload,
        parent: String? = nil, code: String? = nil
    ) throws -> DiagramNodeResponse {
        try store.diagramNodeAdd(DiagramNodeAddRequest(
            diagramUuid: diagramUuid,
            add: DiagramElementAdd(parentElementUuid: parent, code: code, payload: payload)))
    }

    // MARK: - Init

    func testInitDerivesTierChainAndIsIdempotent() throws {
        let first = try initDiagram()
        XCTAssertTrue(first.created)
        XCTAssertEqual(first.diagram.tier, "SESSION")
        // The whole ancestor chain is derived and persisted.
        XCTAssertEqual(first.diagram.projectUuid, "proj-1")
        XCTAssertEqual(first.diagram.instanceUuid, "inst-1")
        XCTAssertEqual(first.diagram.sessionUuid, "sess-1")
        XCTAssertNil(first.diagram.promptUuid)

        let again = try initDiagram()
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.diagram.uuid, first.diagram.uuid)

        let promptTier = try initDiagram(sessionUuid: nil, promptUuid: "prompt-a")
        XCTAssertEqual(promptTier.diagram.tier, "PROMPT")
        XCTAssertEqual(promptTier.diagram.sessionUuid, "sess-1")

        let projectTier = try initDiagram(sessionUuid: nil, projectUuid: "proj-1")
        XCTAssertEqual(projectTier.diagram.tier, "PROJECT")
        XCTAssertNil(projectTier.diagram.instanceUuid)
    }

    func testInitRefusesZeroOrTwoOwners() throws {
        XCTAssertThrowsError(try store.diagramInit(DiagramInitRequest(
            code: "x", name: "X")))
        XCTAssertThrowsError(try store.diagramInit(DiagramInitRequest(
            sessionUuid: "sess-1", promptUuid: "prompt-a", code: "x", name: "X")))
    }

    func testInitUnknownOwnerIsNotFound() throws {
        XCTAssertThrowsError(try initDiagram(sessionUuid: "nope")) { error in
            guard case StoreError.notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
    }

    /// INVERTED BY m0021: a path at PROJECT tier used to be refused because
    /// only an instance had a checkout to anchor it. Screenshots materialize
    /// under CKFS storage now, which every tier has.
    func testInitAcceptsPathAtProjectTier() throws {
        let response = try store.diagramInit(DiagramInitRequest(
            projectUuid: "proj-1", code: "x", name: "X",
            gmccDiagramPath: "docs/x.png"))
        XCTAssertEqual(response.diagram.gmccDiagramPath, "docs/x.png")
        XCTAssertEqual(response.diagram.tier, "PROJECT")
    }

    // MARK: - List (never a union) + Get (three-way absence)

    func testListReturnsOnlyThatTiersRows() throws {
        try initDiagram(code: "sess_one")
        try initDiagram(code: "prompt_one", sessionUuid: nil, promptUuid: "prompt-a")

        let sessionList = try store.diagramList(DiagramListRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(sessionList.diagrams.map(\.code), ["sess_one"])

        let promptList = try store.diagramList(DiagramListRequest(promptUuid: "prompt-a"))
        XCTAssertEqual(promptList.diagrams.map(\.code), ["prompt_one"])

        // Empty list for a real owner with nothing — never an error.
        let projectList = try store.diagramList(DiagramListRequest(projectUuid: "proj-1"))
        XCTAssertTrue(projectList.diagrams.isEmpty)

        XCTAssertThrowsError(try store.diagramList(DiagramListRequest(sessionUuid: "nope")))
    }

    func testGetDiscriminatesAbsenceThreeWays() throws {
        // Unknown owner → NOT_FOUND.
        XCTAssertThrowsError(try store.diagramGet(DiagramGetRequest(sessionUuid: "nope"))) {
            guard case StoreError.notFound = $0 else {
                return XCTFail("expected notFound, got \($0)")
            }
        }
        // Real owner, no diagram → diagramAbsent (wire SUMMARY_ABSENT).
        XCTAssertThrowsError(try store.diagramGet(DiagramGetRequest(sessionUuid: "sess-1"))) {
            guard case StoreError.diagramAbsent = $0 else {
                return XCTFail("expected diagramAbsent, got \($0)")
            }
            XCTAssertEqual(($0 as? StoreError)?.errorPayload.code, .summaryAbsent)
        }
        // Data once one exists.
        let created = try initDiagram()
        let get = try store.diagramGet(DiagramGetRequest(sessionUuid: "sess-1"))
        XCTAssertEqual(get.tree.identity.uuid, created.diagram.uuid)
        // Unknown diagram uuid stays NOT_FOUND.
        XCTAssertThrowsError(try store.diagramGet(DiagramGetRequest(diagramUuid: "nope")))
    }

    func testGetWithSeveralMatchesDemandsCode() throws {
        try initDiagram(code: "alpha")
        try initDiagram(code: "beta")
        XCTAssertThrowsError(try store.diagramGet(DiagramGetRequest(sessionUuid: "sess-1"))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("expected badRequest, got \($0)")
            }
            XCTAssertTrue(detail.contains("alpha"))
            XCTAssertTrue(detail.contains("beta"))
        }
        let get = try store.diagramGet(DiagramGetRequest(sessionUuid: "sess-1", code: "beta"))
        XCTAssertEqual(get.tree.code, "beta")
    }

    // MARK: - Containment + payload agreement

    func testContainmentRulesEnforced() throws {
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(DrawingLayerPayload()))
        let scope = try addElement(diagram.uuid, payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")))

        // A stroke needs a parent...
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .drawingStroke(
            DrawingStrokePayload())))
        // ...and only a drawing_layer parent will do.
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .drawingStroke(
            DrawingStrokePayload()), parent: scope.uuid))
        try addElement(diagram.uuid, payload: .drawingStroke(
            DrawingStrokePayload(vertices: [DiagramVertex(x: 0, y: 0),
                                            DiagramVertex(x: 10, y: 10)])),
                       parent: layer.uuid)

        // dope_entity only under dope_scope.
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), parent: layer.uuid))
        try addElement(diagram.uuid, payload: .dopeEntity(
            DopeEntityPayload(entityCode: "core.user")), parent: scope.uuid)

        // Top-level types refuse a parent.
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .drawingLayer(
            DrawingLayerPayload()), parent: layer.uuid))
    }

    func testPayloadTypeMorphingRefusedOnUpdate() throws {
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(DrawingLayerPayload()))
        XCTAssertThrowsError(try store.diagramNodeUpdate(DiagramNodeUpdateRequest(
            update: DiagramElementUpdate(
                elementUuid: layer.uuid, expectedVersion: 0,
                payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")))))) {
            guard case StoreError.badRequest(let detail) = $0 else {
                return XCTFail("expected badRequest, got \($0)")
            }
            XCTAssertTrue(detail.contains("morphing"))
        }
    }

    func testBindingCodesValidatedButExistenceIsNot() throws {
        let diagram = try initDiagram().diagram
        // A dangling (but well-formed) code is LEGAL — the ghost state.
        try addElement(diagram.uuid, payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "no_such_scope")))
        // A malformed code is refused at write time.
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "Bad-Code"))))
        // Entity codes must parse as 2-segment domain.entity.
        let scope = try addElement(diagram.uuid, payload: .dopeScopePersistenceLayer(
            DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")))
        XCTAssertThrowsError(try addElement(diagram.uuid, payload: .dopeEntity(
            DopeEntityPayload(entityCode: "not_a_ref")), parent: scope.uuid))
    }

    // MARK: - Code minting + defaults

    func testOmittedCodesAreMintedPerType() throws {
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(DrawingLayerPayload()))
        let s1 = try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload()),
                                parent: layer.uuid)
        let s2 = try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload()),
                                parent: layer.uuid)
        let tree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid)).tree
        let layerNode = tree.elements.first { $0.identity.uuid == layer.uuid }
        XCTAssertEqual(layerNode?.base.code, "layer_0001")
        let codes = layerNode?.children.map(\.base.code).sorted()
        XCTAssertEqual(codes, ["stroke_0001", "stroke_0002"])
        XCTAssertNotEqual(s1.uuid, s2.uuid)
        XCTAssertEqual(layerNode?.base.name, "Layer 1")
    }

    // MARK: - Hydration + vertex round trip

    func testTreeHydrationRoundTripsPayloadsAndVertices() throws {
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(
            DrawingLayerPayload(opacity: 0.5, visible: true, locked: true)))
        let vertices = [DiagramVertex(x: 0, y: 0, pressure: 0.4),
                        DiagramVertex(x: 5, y: 9),
                        DiagramVertex(x: -3, y: 12, pressure: 1)]
        try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload(
            tool: .marker, strokeColor: "#ff0000", strokeWidth: 3, vertices: vertices)),
                       parent: layer.uuid, code: "pen")
        try addElement(diagram.uuid, payload: .drawingShape(DrawingShapePayload(
            shapeKind: .rectangle, fillColor: "#00ff00", cornerRadius: 4,
            vertices: [DiagramVertex(x: -10, y: -10), DiagramVertex(x: 10, y: 10)])),
                       parent: layer.uuid, code: "box")

        let tree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid)).tree
        let layerNode = tree.elements[0]
        guard case .drawingLayer(let layerPayload) = layerNode.payload else {
            return XCTFail("expected layer payload")
        }
        XCTAssertEqual(layerPayload.opacity, 0.5)
        XCTAssertTrue(layerPayload.locked)

        let stroke = layerNode.children.first { $0.base.code == "pen" }
        guard case .drawingStroke(let strokePayload) = stroke?.payload else {
            return XCTFail("expected stroke payload")
        }
        XCTAssertEqual(strokePayload.tool, .marker)
        // Strokes persist PACKED (f32 x, f32 y, u8 pressure), so pressure is
        // lossy BY DESIGN — quantized onto 254 steps. The write path
        // normalizes through the same quantization, so what a caller reads
        // back is what was actually stored rather than a value that only
        // looks exact.
        XCTAssertEqual(strokePayload.vertices,
                       DiagramStrokeCodec.normalizedForStorage(vertices))

        let shape = layerNode.children.first { $0.base.code == "box" }
        guard case .drawingShape(let shapePayload) = shape?.payload else {
            return XCTFail("expected shape payload")
        }
        XCTAssertEqual(shapePayload.shapeKind, .rectangle)
        XCTAssertEqual(shapePayload.cornerRadius, 4)
        XCTAssertEqual(shapePayload.vertices.count, 2)
    }

    func testPayloadUpdateReplacesVerticesWholesale() throws {
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(DrawingLayerPayload()))
        let stroke = try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload(
            vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 1, y: 1),
                       DiagramVertex(x: 2, y: 2)])), parent: layer.uuid)
        let updated = try store.diagramNodeUpdate(DiagramNodeUpdateRequest(
            update: DiagramElementUpdate(
                elementUuid: stroke.uuid, expectedVersion: 0,
                payload: .drawingStroke(DrawingStrokePayload(
                    vertices: [DiagramVertex(x: 9, y: 9), DiagramVertex(x: 8, y: 8)])))))
        XCTAssertEqual(updated.version, 1)
        // Strokes moved to packed storage in m0021, so "whole-set
        // replacement" is now asserted against the blob rather than the
        // vertex rows: the packed column holds exactly the new two vertices,
        // and no stroke vertex ROW survives to disagree with it.
        let stored = try store.dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT packed_vertices, vertex_count FROM diagram_drawing_stroke
                 WHERE element_uuid = ?
                """, arguments: [stroke.uuid])
        }
        let packed = try XCTUnwrap(stored?["packed_vertices"] as Data?)
        XCTAssertEqual(stored?["vertex_count"] as Int?, 2)
        XCTAssertEqual(try DiagramStrokeCodec.unpack(packed, count: 2),
                       [DiagramVertex(x: 9, y: 9), DiagramVertex(x: 8, y: 8)])
        let rowCount = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM diagram_stroke_vertex") ?? -1
        }
        XCTAssertEqual(rowCount, 0, "a packed stroke keeps no vertex rows to contradict it")
        // A stale expectedVersion is a VERSION_CONFLICT (the aggregate lock).
        XCTAssertThrowsError(try store.diagramNodeUpdate(DiagramNodeUpdateRequest(
            update: DiagramElementUpdate(elementUuid: stroke.uuid, expectedVersion: 0,
                                         name: "late"))))
    }

    // MARK: - Wire codecs (snake_case round trips per payload case)

    func testPayloadCodecRoundTripsEveryCase() throws {
        let payloads: [DiagramElementPayload] = [
            .drawingLayer(DrawingLayerPayload(opacity: 0.7, visible: false, locked: true)),
            .drawingStroke(DrawingStrokePayload(
                tool: .highlighter, strokeColor: "#123456", strokeWidth: 4,
                vertices: [DiagramVertex(x: 1, y: 2, pressure: 0.5)])),
            .drawingShape(DrawingShapePayload(
                shapeKind: .arrow, strokeColor: "#000000", strokeWidth: 1,
                fillColor: nil, cornerRadius: nil,
                vertices: [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 4, y: 4)])),
            .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            .dopeEntity(DopeEntityPayload(entityCode: "core.user")),
        ]
        for payload in payloads {
            let data = try WireCodec.encoder.encode(payload)
            let decoded = try WireCodec.decoder.decode(DiagramElementPayload.self, from: data)
            XCTAssertEqual(decoded, payload)
            // The tag travels as the element_type raw value.
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertTrue(json.contains("\"kind\":\"\(payload.elementType.rawValue)\""),
                          "missing kind tag in \(json)")
        }
    }

    func testPayloadDecodeFillsSchemaDefaults() throws {
        let sparse = Data(#"{"kind":"drawing_layer","fields":{}}"#.utf8)
        let decoded = try WireCodec.decoder.decode(DiagramElementPayload.self, from: sparse)
        guard case .drawingLayer(let payload) = decoded else {
            return XCTFail("expected layer")
        }
        XCTAssertEqual(payload.opacity, 1)
        XCTAssertTrue(payload.visible)
        XCTAssertFalse(payload.locked)
    }

    func testMutationCodecRoundTrips() throws {
        let mutations: [DiagramMutation] = [
            .elementAdd(DiagramElementAdd(
                clientRef: "tmp1", code: "l1",
                payload: .drawingLayer(DrawingLayerPayload()))),
            .elementUpdate(DiagramElementUpdate(
                elementUuid: "e-1", expectedVersion: 3, centerX: 10)),
            .elementDelete(DiagramElementDelete(elementUuid: "e-2", expectedVersion: 0)),
            .diagramUpdate(DiagramRowUpdate(
                expectedVersion: 1, name: "Renamed",
                gmccDiagramPath: .clear,
                promotion: DiagramPromotion(tier: .session, ownerUuid: "sess-1"))),
        ]
        let data = try WireCodec.encoder.encode(mutations)
        let decoded = try WireCodec.decoder.decode([DiagramMutation].self, from: data)
        XCTAssertEqual(decoded, mutations)
    }

    func testFieldPatchCodec() throws {
        let set = FieldPatch<String>.set("docs/x.png")
        let clear = FieldPatch<String>.clear
        let setData = try WireCodec.encoder.encode(set)
        let clearData = try WireCodec.encoder.encode(clear)
        XCTAssertEqual(try WireCodec.decoder.decode(FieldPatch<String>.self, from: setData), set)
        XCTAssertEqual(try WireCodec.decoder.decode(FieldPatch<String>.self, from: clearData), clear)
        XCTAssertTrue(String(data: setData, encoding: .utf8)!.contains("\"op\":\"set\""))
    }
}

/// Registry drift guards: DiagramElementTypeSpec is the single truth for
/// subtype persistence and containment — a table rename or a containment
/// change must show up here before it ships.
extension DiagramMachineTests {

    func testElementTypeRegistryIsTotalAndNamesRealTables() throws {
        for type in DiagramElementType.allCases {
            let spec = DiagramElementTypeSpec.spec(for: type)
            XCTAssertEqual(spec.type, type)
            let tables = try store.dbQueue.read { db in
                try String.fetchAll(db, sql: """
                    SELECT name FROM sqlite_master WHERE type = 'table'
                    """)
            }
            XCTAssertTrue(tables.contains(spec.subtypeTable),
                          "\(type.rawValue) subtype table \(spec.subtypeTable) missing from schema")
            if let vertexTable = spec.vertexTable {
                XCTAssertTrue(tables.contains(vertexTable),
                              "\(type.rawValue) vertex table \(vertexTable) missing from schema")
                XCTAssertNotNil(spec.vertexParentColumn)
            } else {
                XCTAssertNil(spec.vertexParentColumn)
            }
        }
    }

    func testElementTypeRegistryContainmentMatchesTheSpec() {
        // Top-level types: dope_scope + drawing_layer, exactly.
        let topLevel = DiagramElementType.allCases
            .filter { DiagramElementTypeSpec.spec(for: $0).allowedParentTypes == nil }
        XCTAssertEqual(Set(topLevel), [.dopeScopePersistenceLayer, .drawingLayer])
        XCTAssertEqual(DiagramElementTypeSpec.spec(for: .drawingStroke).allowedParentTypes,
                       [.drawingLayer])
        XCTAssertEqual(DiagramElementTypeSpec.spec(for: .drawingShape).allowedParentTypes,
                       [.drawingLayer])
        XCTAssertEqual(DiagramElementTypeSpec.spec(for: .dopeEntity).allowedParentTypes,
                       [.dopeScopePersistenceLayer])
        XCTAssertEqual(DiagramElementType.allCases.filter {
            DiagramElementTypeSpec.spec(for: $0).isDopeBinding
        }.sorted { $0.rawValue < $1.rawValue }, [.dopeEntity, .dopeScopePersistenceLayer])
    }

    func testMintPrefixesAreDistinctAndMintIgnoresAbsurdSuffixes() throws {
        XCTAssertEqual(Set(DiagramElementType.allCases.map(\.codePrefix)).count,
                       DiagramElementType.allCases.count)
        let diagram = try initDiagram().diagram
        let layer = try addElement(diagram.uuid, payload: .drawingLayer(DrawingLayerPayload()))
        // A crafted near-Int.max suffix must not overflow the next mint, and
        // a LIKE-wildcard perturbation (strokes9000 matching stroke_%'s
        // underscore-as-wildcard) must not perturb the sequence either.
        try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload()),
                       parent: layer.uuid, code: "stroke_9223372036854775807")
        try addElement(diagram.uuid, payload: .drawingStroke(DrawingStrokePayload()),
                       parent: layer.uuid, code: "strokes9000")
        let minted = try addElement(diagram.uuid,
                                    payload: .drawingStroke(DrawingStrokePayload()),
                                    parent: layer.uuid)
        let tree = try store.diagramGet(DiagramGetRequest(diagramUuid: diagram.uuid)).tree
        let mintedCode = tree.elements[0].children
            .first { $0.identity.uuid == minted.uuid }?.base.code
        XCTAssertEqual(mintedCode, "stroke_0001")
    }
}
