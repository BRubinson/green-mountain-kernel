import Foundation
import GRDB

/// DIAGRAM domain modeling — db-persisted canvases over the dope subsystem.
///
/// One write path: `applyDiagramMutations` is the ONLY mutation body. The
/// granular node verbs build one-mutation batches over it, so granular and
/// batch semantics structurally cannot drift. Every batch (of any size) runs
/// in one transaction, bumps `diagram.revision` exactly once
/// (`bumpDiagramRevision` — the bumpScopeRevision twin: never the row's
/// optimistic-lock version) and emits exactly one DIAGRAM_CHANGE event.
///
/// dope bindings are TEXT codes resolved at READ time through the existing
/// `dopeScopeCandidates` ladder against the diagram row's own session/prompt
/// FKs. Dangling codes are a LEGAL renderable state (ghosts) — diagram
/// elements never join `requireNoExternalReferrers`, and no dope write path
/// knows diagrams exist.
/// DIAGRAM data access half — see the facade header in Store+Diagram.swift.
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts. Internal helpers keep their explicit `db` parameter —
/// verbatim moves from the Store extension.
struct DiagramOwner {
    let tier: DiagramTier
    let projectUuid: String
    /// DERIVED, never an ownership tier since m0021: a session's
    /// instance, resolved through the join. The diagram row no longer
    /// stores it; callers that genuinely need a checkout (nothing does,
    /// after rendering moved to CKFS storage) still get it here.
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?

    var ownerKind: String { tier.rawValue.lowercased() }
    var ownerColumn: String {
        switch tier {
        case .project: return "project_uuid"
        case .session: return "session_uuid"
        case .prompt: return "prompt_uuid"
        }
    }
    var ownerUuid: String {
        switch tier {
        case .project: return projectUuid
        case .session: return sessionUuid!
        case .prompt: return promptUuid!
        }
    }
}

struct ElementRowInfo {
    let uuid: String
    let diagramUuid: String
    let parentElementUuid: String?
    let type: DiagramElementType
}

struct DiagramRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// The diagram projection.
    ///
    /// m0021 dropped the stored `instance_uuid` column — INSTANCE is no
    /// longer an ownership tier — but a session-owned diagram still HAS an
    /// instance, and `DiagramRow.instanceUuid` is an existing wire field
    /// that consumers read. So it is DERIVED here through the session join
    /// rather than removed: the ownership ladder shrank, the ancestry did
    /// not. A project-tier diagram genuinely has no single instance and
    /// reports nil, which is exactly the fact that made the tier removable.
    ///
    /// Every `diagram` read goes through this, so `d.` qualification is
    /// required in the WHERE clauses (session shares uuid/code/name).
    static let diagramSelect = """
        SELECT d.*, s.instance_uuid AS instance_uuid
          FROM diagram d LEFT JOIN session s ON s.uuid = d.session_uuid
        """

    /// diagramSelect is a PROJECTION join, so the fetch stays on Row: the
    /// record decodes the `d.*` half and the derived `instance_uuid` rides
    /// alongside it. Throws now, because Record decode does -- previously a
    /// drifted row would have taken down the process through Row's try!
    /// subscripts.
    static func diagramRow(_ row: Row) throws -> DiagramRow {
        try DiagramRecord(row: row).wireRow(instanceUuid: row["instance_uuid"])
    }


    /// The ITEM-tier restriction on a diagram's whole-canvas dope binding.
    ///
    /// This is a Swift guard rather than a SQL CHECK because it cannot be
    /// one: a SQLite CHECK cannot reference another table, and ALTER TABLE
    /// ADD COLUMN cannot add a CHECK at all. That matches the per-element
    /// binding, which is also a code and never an FK.
    ///
    /// The rule is deliberately asymmetric between write and read. On WRITE a
    /// binding that resolves to a base tier is refused, so a canvas can never
    /// be pointed at shared truth by accident. On READ a code that resolves to
    /// nothing is a legal ghost — a base is free to evolve out from under a
    /// diagram, exactly as with the per-element bindings.
    func validateDiagramScopeBinding(
        owner: DiagramOwner, code: String
    ) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT scope_type FROM dope_scope
             WHERE project_uuid = ? AND code = ? AND deleted_on IS NULL
            """, arguments: [owner.projectUuid, code])
        // Unknown code: legal, a ghost. Nothing to restrict yet.
        guard !rows.isEmpty else { return }
        let tiers = rows.compactMap { DopeScopeType(fromWire: $0["scope_type"] as String) }
        guard tiers.contains(where: \.isOverlay) else {
            throw StoreError.badRequest(
                detail: "diagram dope binding '\(code)' resolves only to base tier(s) "
                      + tiers.map(\.rawValue).joined(separator: ", ")
                      + " — a diagram must bind to a masking scope "
                      + "(PROJECT_ITEM / SESSION_INSTANCE_ITEM) so edits land on an overlay")
        }
    }

    // MARK: - Row + revision helpers



    func fetchDiagram(uuid: String) throws -> DiagramRow? {
        try Row.fetchOne(db, sql: "\(Self.diagramSelect) WHERE d.uuid = ?", arguments: [uuid])
            .map(Self.diagramRow)
    }

    /// Advance the whole-tree content counter WITHOUT bumping the diagram
    /// row's version — a geometry edit deep in the tree must never invalidate
    /// a diagram version a GMVibes editor is holding.
    @discardableResult
    func bumpDiagramRevision(diagramUuid: String) throws -> Int64 {
        try db.execute(
            sql: "UPDATE diagram SET revision = revision + 1, updated_at = ? WHERE uuid = ?",
            arguments: [Store.isoNow(), diagramUuid])
        guard let revision = try Int64.fetchOne(
            db, sql: "SELECT revision FROM diagram WHERE uuid = ?", arguments: [diagramUuid]
        ) else {
            throw StoreError.notFound(entity: "diagram", key: diagramUuid)
        }
        return revision
    }

    func recordDiagramChange(
        diagram: DiagramRow, action: String,
        elementUuid: String?, mutationCount: Int?, revision: Int64
    ) throws {
        var payload: [String: Any] = [
            "action": action,
            "diagram_uuid": diagram.uuid,
            "tier": diagram.tier,
            "project_uuid": diagram.projectUuid,
            "revision": Int(revision),
        ]
        if let elementUuid { payload["element_uuid"] = elementUuid }
        if let mutationCount { payload["mutation_count"] = mutationCount }
        if let sessionUuid = diagram.sessionUuid { payload["session_uuid"] = sessionUuid }
        if let promptUuid = diagram.promptUuid { payload["prompt_uuid"] = promptUuid }
        try core.appendEvent(db, kind: .diagramChange, subjectUuid: diagram.uuid,
                        payload: Store.jsonPayload(payload))
        // touchSession only when session-owned — PROJECT/INSTANCE-tier
        // diagrams have no session to touch.
        if let sessionUuid = diagram.sessionUuid {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    // MARK: - Owner addressing (the chain-non-null tier ladder)



    /// Validate that EXACTLY one owner uuid was passed, that the row exists
    /// (unknown uuid → NOT_FOUND, the three-way absence discrimination's
    /// first guard), and derive the full ancestor chain by joins.
    func resolveDiagramOwner(
        projectUuid: String?, instanceUuid: String?,
        sessionUuid: String?, promptUuid: String?
    ) throws -> DiagramOwner {
        // instanceUuid is still ACCEPTED so a caller passing the retired
        // flag gets a real explanation rather than "pass exactly one owner".
        if instanceUuid != nil {
            throw StoreError.badRequest(detail:
                "the INSTANCE diagram tier was removed by m0021 — a diagram is owned by a "
                + "project, a session, or a prompt. Pass --session-uuid for the session that "
                + "lives in that instance, or --project-uuid for the whole project.")
        }
        let owners: [(String?, DiagramTier)] = [
            (projectUuid, .project),
            (sessionUuid, .session), (promptUuid, .prompt),
        ]
        let present = owners.filter { $0.0 != nil }
        guard present.count == 1, let (uuid, tier) = present.first, let uuid else {
            throw StoreError.badRequest(detail:
                "pass exactly one of project/session/prompt uuid (got \(present.count))")
        }
        switch tier {
        case .project:
            guard try Row.fetchOne(
                db, sql: "SELECT uuid FROM project WHERE uuid = ?", arguments: [uuid]
            ) != nil else {
                throw StoreError.notFound(entity: "project", key: uuid)
            }
            return DiagramOwner(tier: .project, projectUuid: uuid,
                                instanceUuid: nil, sessionUuid: nil, promptUuid: nil)
        case .session:
            guard let row = try Row.fetchOne(db, sql: """
                SELECT s.instance_uuid AS instance_uuid, i.project_uuid AS project_uuid
                FROM session s JOIN instance i ON i.uuid = s.instance_uuid
                WHERE s.uuid = ?
                """, arguments: [uuid]) else {
                throw StoreError.notFound(entity: "session", key: uuid)
            }
            return DiagramOwner(tier: .session, projectUuid: row["project_uuid"],
                                instanceUuid: row["instance_uuid"],
                                sessionUuid: uuid, promptUuid: nil)
        case .prompt:
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.session_uuid AS session_uuid, s.instance_uuid AS instance_uuid,
                       i.project_uuid AS project_uuid
                FROM prompt p
                JOIN session s ON s.uuid = p.session_uuid
                JOIN instance i ON i.uuid = s.instance_uuid
                WHERE p.uuid = ?
                """, arguments: [uuid]) else {
                throw StoreError.notFound(entity: "prompt", key: uuid)
            }
            return DiagramOwner(tier: .prompt, projectUuid: row["project_uuid"],
                                instanceUuid: row["instance_uuid"],
                                sessionUuid: row["session_uuid"], promptUuid: uuid)
        }
    }

    // MARK: - Init

    func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try DopeCode.validateCode(req.code, field: "diagram code")
        let description = req.description ?? ""
        guard description.count <= 512 else {
            throw StoreError.badRequest(detail: "diagram description exceeds 512 characters")
        }
        let owner = try resolveDiagramOwner(
            projectUuid: req.projectUuid, instanceUuid: req.instanceUuid,
            sessionUuid: req.sessionUuid, promptUuid: req.promptUuid)
        if let binding = req.dopeScopeCode {
            try validateDiagramScopeBinding(owner: owner, code: binding)
        }
        if let existing = try Row.fetchOne(db, sql: """
            \(Self.diagramSelect)
             WHERE d.tier = ? AND d.\(owner.ownerColumn) = ? AND d.code = ?
            """, arguments: [owner.tier.rawValue, owner.ownerUuid, req.code]) {
            return DiagramResponse(diagram: try Self.diagramRow(existing), created: false)
        }
        let uuid = try core.insertBase(db, table: "diagram", extra: [
            "project_uuid": owner.projectUuid,
            "session_uuid": owner.sessionUuid,
            "prompt_uuid": owner.promptUuid,
            "tier": owner.tier.rawValue,
            "code": req.code,
            "name": req.name,
            "description": description,
            "gmcc_diagram_path": req.gmccDiagramPath,
            "dope_scope_code": req.dopeScopeCode,
            "revision": 0,
        ])
        guard let diagram = try fetchDiagram(uuid: uuid) else {
            throw StoreError.corruptState(entity: "diagram", detail: "vanished after insert")
        }
        try recordDiagramChange(diagram: diagram, action: "init",
                                     elementUuid: nil, mutationCount: nil,
                                     revision: diagram.revision)
        return DiagramResponse(diagram: diagram, created: true)
    }

    // MARK: - List (v12 semantics: one owner, one tier, never a union)

    func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        if let visibility = req.visibility, DiagramVisibility(rawValue: visibility) == nil {
            throw StoreError.badRequest(detail:
                "unknown visibility '\(visibility)' (PRIVATE|PUBLIC)")
        }
        let owner = try resolveDiagramOwner(
            projectUuid: req.projectUuid, instanceUuid: req.instanceUuid,
            sessionUuid: req.sessionUuid, promptUuid: req.promptUuid)
        var sql = """
            \(Self.diagramSelect)
             WHERE d.tier = ? AND d.\(owner.ownerColumn) = ?
            """
        var args: [any DatabaseValueConvertible] = [owner.tier.rawValue, owner.ownerUuid]
        if let visibility = req.visibility {
            sql += " AND d.visibility = ?"
            args.append(visibility)
        }
        sql += " ORDER BY d.code"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        return DiagramListResponse(diagrams: try rows.map(Self.diagramRow))
    }

    // MARK: - Get (uuid or owner+code; no cross-tier ladder)

    func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        let diagram: DiagramRow
        if let diagramUuid = req.diagramUuid {
            guard let found = try fetchDiagram(uuid: diagramUuid) else {
                throw StoreError.notFound(entity: "diagram", key: diagramUuid)
            }
            diagram = found
        } else {
            let owner = try resolveDiagramOwner(
                projectUuid: req.projectUuid, instanceUuid: req.instanceUuid,
                sessionUuid: req.sessionUuid, promptUuid: req.promptUuid)
            var sql = "\(Self.diagramSelect) WHERE d.tier = ? AND d.\(owner.ownerColumn) = ?"
            var args: [(any DatabaseValueConvertible)?] = [owner.tier.rawValue, owner.ownerUuid]
            if let code = req.code {
                sql += " AND d.code = ?"
                args.append(code)
            }
            sql += " ORDER BY d.code"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                .map(Self.diagramRow)
            if rows.count > 1 {
                throw StoreError.badRequest(detail:
                    "several diagrams match — pass --code (candidates: "
                    + rows.map(\.code).joined(separator: ", ") + ")")
            }
            guard let found = rows.first else {
                // The owner exists (resolveDiagramOwner's guard) — this
                // absence means "initialize a diagram", not "unknown uuid".
                throw StoreError.diagramAbsent(
                    ownerKind: owner.ownerKind, ownerUuid: owner.ownerUuid, code: req.code)
            }
            diagram = found
        }
        let tree = try fetchDiagramTree(diagram: diagram)
        let bindings = try resolveDiagramBindings(diagram: diagram, tree: tree)
        return DiagramGetResponse(
            tree: tree, bindings: bindings,
            ownerStoragePath: try diagramOwnerStoragePath(diagram: diagram))
    }

    /// The CKFS storage directory of whichever tier owns this diagram.
    ///
    /// This is the root rendered output is written under. Every tier carries the
    /// column, which is precisely why CKFS storage works at project tier
    /// where an instance checkout did not.
    func diagramOwnerStoragePath(diagram: DiagramRow) throws -> String? {
        guard let tier = DiagramTier(rawValue: diagram.tier) else { return nil }
        let (table, uuid): (String, String?)
        switch tier {
        case .project: (table, uuid) = ("project", diagram.projectUuid)
        case .session: (table, uuid) = ("session", diagram.sessionUuid)
        case .prompt: (table, uuid) = ("prompt", diagram.promptUuid)
        }
        guard let uuid else { return nil }
        let path = try String.fetchOne(db, sql: """
            SELECT ckfs_relative_storage_path FROM \(table) WHERE uuid = ?
            """, arguments: [uuid])
        // Empty is as good as absent: a caller must not build a path that
        // silently resolves to the CKFS root itself.
        return (path?.isEmpty ?? true) ? nil : path
    }

    // MARK: - Hydration (8 flat queries grouped in Swift — never per-node
    // recursion; ORDER BY element_z, sort_order, code keeps reads and
    // screenshots deterministic)

    func fetchDiagramTree(diagram: DiagramRow) throws -> DiagramTree {
        let elementRows = try DiagramElementRecord.fetchAll(
            db, where: "diagram_uuid = ?", arguments: [diagram.uuid],
            orderBy: "element_z, sort_order, code")

        // Filter-only join: every projected column comes from the subtype
        // table, the join only narrows to this diagram. The record supplies
        // its own table name, so the eight call sites lose their string
        // literals as well as their subscripts.
        func subtypeRecords<R: DiagramSubtypeRecord>(_: R.Type) throws -> [String: R] {
            let rows = try R.fetchAll(db, sql: """
                SELECT t.* FROM \(R.databaseTableName) t
                JOIN diagram_element e ON e.uuid = t.element_uuid
                WHERE e.diagram_uuid = ?
                """, arguments: [diagram.uuid])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.elementUuid, $0) })
        }
        let layers = try subtypeRecords(DiagramDrawingLayerRecord.self)
        let strokes = try subtypeRecords(DiagramDrawingStrokeRecord.self)
        let shapes = try subtypeRecords(DiagramDrawingShapeRecord.self)
        let scopes = try subtypeRecords(DiagramDopeScopePersistenceLayerRecord.self)
        let entities = try subtypeRecords(DiagramDopeEntityRecord.self)
        let texts = try subtypeRecords(DiagramDrawingTextRecord.self)
        let connectors = try subtypeRecords(DiagramConnectorRecord.self)
        let umlNodes = try subtypeRecords(DiagramUmlNodeRecord.self)

        // The vertex fetch CANNOT stay generic. diagram_stroke_vertex has a
        // `pressure` column and diagram_shape_vertex does not, which the old
        // shared helper papered over with a row.hasColumn("pressure") guard --
        // i.e. the distinction was decided by the result set. Under records it
        // is decided by the schema, which means two concrete functions.
        func strokeVertices() throws -> [String: [DiagramVertex]] {
            let rows = try DiagramStrokeVertexRecord.fetchAll(db, sql: """
                SELECT v.* FROM diagram_stroke_vertex v
                JOIN diagram_element e ON e.uuid = v.stroke_element_uuid
                WHERE e.diagram_uuid = ? ORDER BY v.seq
                """, arguments: [diagram.uuid])
            var grouped = [String: [DiagramVertex]]()
            for row in rows {
                grouped[row.strokeElementUuid, default: []].append(
                    DiagramVertex(x: row.x, y: row.y, pressure: row.pressure))
            }
            return grouped
        }
        func shapeVertices() throws -> [String: [DiagramVertex]] {
            let rows = try DiagramShapeVertexRecord.fetchAll(db, sql: """
                SELECT v.* FROM diagram_shape_vertex v
                JOIN diagram_element e ON e.uuid = v.shape_element_uuid
                WHERE e.diagram_uuid = ? ORDER BY v.seq
                """, arguments: [diagram.uuid])
            var grouped = [String: [DiagramVertex]]()
            for row in rows {
                grouped[row.shapeElementUuid, default: []].append(
                    // No pressure column on this table -- previously the
                    // hasColumn guard's nil branch.
                    DiagramVertex(x: row.x, y: row.y, pressure: nil))
            }
            return grouped
        }
        let strokeVertexRows = try strokeVertices()
        let shapeVertexRows = try shapeVertices()

        func payload(for row: DiagramElementRecord) throws -> DiagramElementPayload {
            let uuid = row.uuid
            guard let type = DiagramElementType(rawValue: row.elementType) else {
                throw StoreError.corruptState(
                    entity: "diagram_element",
                    detail: "unknown element_type '\(row.elementType)'")
            }
            switch type {
            case .drawingLayer:
                guard let sub = layers[uuid] else { break }
                return .drawingLayer(DrawingLayerPayload(
                    opacity: sub.opacity,
                    visible: sub.visible,
                    locked: sub.locked))
            case .drawingStroke:
                guard let sub = strokes[uuid] else { break }
                // Read precedence, per the storage-strategy axis: the packed
                // blob when present, else the vertex rows. The write path
                // never leaves both populated. The old hasColumn("packed_vertices")
                // guard is gone -- the column is always decoded now, so the
                // question is purely whether it is NULL.
                let packed: [DiagramVertex]?
                if let blob = sub.packedVertices, let count = sub.vertexCount {
                    packed = try DiagramStrokeCodec.unpack(blob, count: Int(count))
                } else {
                    packed = nil
                }
                return .drawingStroke(DrawingStrokePayload(
                    tool: DiagramStrokeTool(rawValue: sub.tool) ?? .pencil,
                    strokeColor: sub.strokeColor, strokeWidth: sub.strokeWidth,
                    vertices: packed ?? strokeVertexRows[uuid] ?? []))
            case .drawingShape:
                guard let sub = shapes[uuid] else { break }
                guard let kind = DiagramShapeKind(rawValue: sub.shapeKind) else {
                    throw StoreError.corruptState(
                        entity: "diagram_drawing_shape",
                        detail: "unknown shape_kind '\(sub.shapeKind)'")
                }
                return .drawingShape(DrawingShapePayload(
                    shapeKind: kind, strokeColor: sub.strokeColor,
                    strokeWidth: sub.strokeWidth, fillColor: sub.fillColor,
                    cornerRadius: sub.cornerRadius,
                    vertices: shapeVertexRows[uuid] ?? []))
            case .drawingText:
                guard let sub = texts[uuid] else { break }
                return .drawingText(DrawingTextPayload(
                    markdown: sub.markdown, width: sub.width, height: sub.height,
                    fontSize: sub.fontSize, textColor: sub.textColor,
                    backgroundColor: sub.backgroundColor))
            case .connector:
                guard let sub = connectors[uuid] else { break }
                return .connector(ConnectorPayload(
                    targetElementUuid: sub.targetElementUuid,
                    strokeColor: sub.strokeColor, strokeWidth: sub.strokeWidth,
                    lineStyle: DiagramConnectorLineStyle(
                        rawValue: sub.lineStyle) ?? .solid,
                    headKind: DiagramConnectorHead(rawValue: sub.headKind) ?? .arrow,
                    routingKind: DiagramConnectorRouting(
                        rawValue: sub.routingKind) ?? .orthogonalStep,
                    tailKind: DiagramConnectorHead(rawValue: sub.tailKind) ?? .none,
                    label: sub.label))
            case .umlNode:
                guard let sub = umlNodes[uuid] else { break }
                guard let kind = DiagramNodeKind(rawValue: sub.nodeKind) else {
                    throw StoreError.corruptState(
                        entity: "diagram_uml_node",
                        detail: "unknown node_kind '\(sub.nodeKind)'")
                }
                return .umlNode(UmlNodePayload(
                    nodeKind: kind, width: sub.width, height: sub.height,
                    markdown: sub.markdown, fontSize: sub.fontSize,
                    textColor: sub.textColor, strokeColor: sub.strokeColor,
                    strokeWidth: sub.strokeWidth, fillColor: sub.fillColor))
            case .dopeScopePersistenceLayer:
                guard let sub = scopes[uuid] else { break }
                return .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: sub.dopeScopeCode))
            case .dopeEntity:
                guard let sub = entities[uuid] else { break }
                return .dopeEntity(DopeEntityPayload(entityCode: sub.entityCode))
            }
            throw StoreError.corruptState(
                entity: "diagram_element", detail: "element \(uuid) has no subtype row")
        }

        var childrenByParent = [String: [DiagramElementRecord]]()
        var topLevel: [DiagramElementRecord] = []
        for row in elementRows {
            if let parent = row.parentElementUuid {
                childrenByParent[parent, default: []].append(row)
            } else {
                topLevel.append(row)
            }
        }

        func node(_ row: DiagramElementRecord) throws -> DiagramElementNode {
            DiagramElementNode(
                identity: DopeNodeIdentity(
                    uuid: row.uuid, version: row.version,
                    createdAt: row.createdAt, updatedAt: row.updatedAt),
                base: DiagramElementBase(
                    code: row.code, name: row.name, description: row.description,
                    sortOrder: Int(row.sortOrder), centerX: row.centerX,
                    centerY: row.centerY, elementZ: row.elementZ,
                    scale: row.scale),
                payload: try payload(for: row),
                children: try (childrenByParent[row.uuid] ?? []).map(node))
        }

        return DiagramTree(
            identity: DopeNodeIdentity(uuid: diagram.uuid, version: diagram.version,
                                       createdAt: diagram.createdAt, updatedAt: diagram.updatedAt),
            tier: diagram.tier, projectUuid: diagram.projectUuid,
            instanceUuid: diagram.instanceUuid, sessionUuid: diagram.sessionUuid,
            promptUuid: diagram.promptUuid, code: diagram.code, name: diagram.name,
            description: diagram.description, gmccDiagramPath: diagram.gmccDiagramPath,
            revision: diagram.revision, elements: try topLevel.map(node))
    }

    // MARK: - Binding resolution (read-time, ghost-tolerant)

    /// One row per dope_scope element, resolved through the EXISTING dope
    /// ladder against the DIAGRAM row's own session/prompt context: PROMPT
    /// scope preferred, SESSION_INSTANCE fallback, resolvedVia surfaced. A
    /// PROJECT/INSTANCE-tier diagram has no session — every binding resolves
    /// absent by construction. Never an error, never a dope delete guard.
    func resolveDiagramBindings(
        diagram: DiagramRow, tree: DiagramTree
    ) throws -> [DiagramBindingResolution] {
        var bindings: [DiagramBindingResolution] = []

        func walk(_ node: DiagramElementNode) throws {
            if case .dopeScopePersistenceLayer(let payload) = node.payload {
                var resolvedVia: String?
                var scope: DopeScopeRow?
                if let sessionUuid = diagram.sessionUuid {
                    if let promptUuid = diagram.promptUuid {
                        scope = try dope.dopeScopeCandidates(
                            sessionUuid: sessionUuid, scopeType: .sessionInstanceItem,
                            promptUuid: promptUuid, code: payload.dopeScopeCode).first
                        if scope != nil { resolvedVia = "prompt" }
                    }
                    if scope == nil {
                        scope = try dope.dopeScopeCandidates(
                            sessionUuid: sessionUuid, scopeType: .sessionInstance,
                            code: payload.dopeScopeCode).first
                        if scope != nil { resolvedVia = "session_base" }
                    }
                } else {
                    // PROJECT tier: no session, so the session ladder above
                    // resolves nothing and every element would ghost. This
                    // rung is what makes a project-level persistence diagram
                    // render actual cards — the masking PROJECT_ITEM scope
                    // first, then the BASE_PROJECT scope DOPE_PROMOTE
                    // maintains, mirroring the session ladder exactly.
                    scope = try dope.dopeProjectScopeCandidates(
                        projectUuid: diagram.projectUuid, scopeType: .projectItem,
                        code: payload.dopeScopeCode).first
                    if scope != nil { resolvedVia = "project_item" }
                    if scope == nil {
                        scope = try dope.dopeProjectScopeCandidates(
                            projectUuid: diagram.projectUuid, scopeType: .baseProject,
                            code: payload.dopeScopeCode).first
                        if scope != nil { resolvedVia = "base_project" }
                    }
                }
                bindings.append(DiagramBindingResolution(
                    elementUuid: node.identity.uuid,
                    dopeScopeCode: payload.dopeScopeCode,
                    resolvedVia: resolvedVia,
                    scopeUuid: scope?.uuid,
                    dopeRevision: scope?.revision))
            }
            for child in node.children { try walk(child) }
        }
        for element in tree.elements { try walk(element) }
        return bindings
    }

    // MARK: - Element validation + code minting



    func fetchElementInfo(uuid: String) throws -> ElementRowInfo {
        guard let row = try Row.fetchOne(
            db, sql: "SELECT * FROM diagram_element WHERE uuid = ?", arguments: [uuid]
        ) else {
            throw StoreError.notFound(entity: "diagram_element", key: uuid)
        }
        guard let type = DiagramElementType(rawValue: row["element_type"]) else {
            throw StoreError.corruptState(
                entity: "diagram_element",
                detail: "unknown element_type '\(row["element_type"] as String)'")
        }
        return ElementRowInfo(uuid: row["uuid"], diagramUuid: row["diagram_uuid"],
                              parentElementUuid: row["parent_element_uuid"], type: type)
    }

    /// Containment + payload shape: the cross-row rules the schema cannot
    /// see (which parent types may hold which child types), plus code
    /// validation on binding payloads. Existence of the dope target is
    /// deliberately NOT checked — dangling is legal.
    func validateDiagramElementShape(
        diagramUuid: String, type: DiagramElementType,
        parent: ElementRowInfo?, payload: DiagramElementPayload
    ) throws {
        guard payload.elementType == type else {
            throw StoreError.badRequest(detail:
                "payload kind '\(payload.elementType.rawValue)' does not match element type '\(type.rawValue)' — type morphing is refused")
        }
        let spec = DiagramElementTypeSpec.spec(for: type)
        if let allowed = spec.allowedParentTypes {
            guard let parent else {
                throw StoreError.badRequest(detail:
                    "\(type.rawValue) elements need a parent element ("
                    + allowed.map(\.rawValue).sorted().joined(separator: "/") + ")")
            }
            guard allowed.contains(parent.type) else {
                throw StoreError.badRequest(detail:
                    "a \(type.rawValue) cannot live under a \(parent.type.rawValue) (legal: "
                    + allowed.map(\.rawValue).sorted().joined(separator: "/") + ")")
            }
            guard parent.diagramUuid == diagramUuid else {
                throw StoreError.badRequest(detail:
                    "parent element \(parent.uuid) belongs to a different diagram")
            }
        } else if parent != nil {
            throw StoreError.badRequest(detail:
                "\(type.rawValue) is a top-level element type and cannot have a parent")
        }
        switch payload {
        case .dopeScopePersistenceLayer(let p):
            try DopeCode.validateCode(p.dopeScopeCode, field: "dope_scope binding code")
        case .dopeEntity(let p):
            _ = try DopeCode.parseEntityRef(p.entityCode, field: "dope entity binding")
        case .drawingStroke(let p):
            if !p.vertices.isEmpty, p.vertices.count < 2 {
                throw StoreError.badRequest(detail: "a stroke needs at least 2 vertices (or none)")
            }
        case .drawingShape(let p):
            if p.cornerRadius != nil, p.shapeKind != .rectangle {
                throw StoreError.badRequest(detail: "corner_radius is only legal on rectangles")
            }
        case .drawingText(let p):
            guard p.width > 0, p.height > 0 else {
                throw StoreError.badRequest(
                    detail: "a text box needs a positive width and height")
            }
            guard p.fontSize > 0 else {
                throw StoreError.badRequest(detail: "a text box needs a positive font size")
            }
        case .umlNode(let p):
            guard p.width > 0, p.height > 0 else {
                throw StoreError.badRequest(
                    detail: "a uml node needs a positive width and height")
            }
            if let fontSize = p.fontSize, fontSize <= 0 {
                throw StoreError.badRequest(
                    detail: "a uml node's font size must be positive when set")
            }
            if let strokeWidth = p.strokeWidth, strokeWidth <= 0 {
                throw StoreError.badRequest(
                    detail: "a uml node's stroke width must be positive when set")
            }
        case .connector(let p):
            guard p.strokeWidth > 0 else {
                throw StoreError.badRequest(detail: "a connector needs a positive stroke width")
            }
            // The endpoint's containment rule needs the TARGET's parentage,
            // which this payload-shape pass does not have — it lands in
            // validateConnectorTarget, called with the db in hand.
            _ = p.targetElementUuid
        case .drawingLayer:
            break
        }
    }

    /// The connector containment rule, evaluated with SQL lookups.
    ///
    /// DiagramTreeReducer answers the same question by walking its in-memory
    /// tree. Both call DiagramContainment, so the RULE is shared even though
    /// the lookups cannot be — the only way a rule this fiddly stays
    /// identical across the two implementations the parity oracle compares.
    func validateConnectorTarget(
        diagramUuid: String, referrerUuid: String,
        parentOfReferrer: String?, targetUuid: String
    ) throws {
        let spec = DiagramElementTypeSpec.spec(for: .connector)
        guard let ref = spec.elementRefs.first else { return }

        func parentOf(_ uuid: String) throws -> String? {
            try String.fetchOne(
                db, sql: "SELECT parent_element_uuid FROM diagram_element WHERE uuid = ?",
                arguments: [uuid])
        }
        // Same-diagram containment is part of the rule: a connector may
        // never reach across canvases.
        let targetDiagram = try String.fetchOne(
            db, sql: "SELECT diagram_uuid FROM diagram_element WHERE uuid = ?",
            arguments: [targetUuid])
        let targetExists = targetDiagram == diagramUuid
        let grandparent = try parentOfReferrer.flatMap { try parentOf($0) }

        if let violation = DiagramContainment.validateReference(
            rule: ref.rule,
            referrerUuid: referrerUuid,
            parentOfReferrer: parentOfReferrer,
            grandparentOfReferrer: grandparent,
            targetUuid: targetUuid,
            parentOfTarget: targetExists ? try parentOf(targetUuid) : nil,
            targetExists: targetExists
        ) {
            throw StoreError.badRequest(
                detail: violation.message(role: "connector \(ref.role)",
                                          referrer: referrerUuid, target: targetUuid))
        }
    }

    /// Mint `stroke_0007`-style codes when an add omits one — hand-naming
    /// hundreds of freedraw strokes is hostile. MAX numeric suffix + 1 per
    /// type prefix within the diagram-wide code namespace.
    ///
    /// The LIKE underscore is ESCAPEd (it is a single-char wildcard, so a
    /// bare `stroke_%` would also match `strokes9000`), and suffixes are
    /// bounded before the +1 so a crafted 19-digit code can never overflow
    /// Int and trap the shared single-writer daemon — absurd suffixes are
    /// simply ignored by the mint.
    private static let maxMintedSuffix = 999_999

    private func mintElementCode(
        diagramUuid: String, type: DiagramElementType
    ) throws -> String {
        let prefix = type.codePrefix + "_"
        let pattern = prefix.replacingOccurrences(of: "_", with: "\\_") + "%"
        let existing = try String.fetchAll(db, sql: """
            SELECT code FROM diagram_element WHERE diagram_uuid = ? AND code LIKE ? ESCAPE '\\'
            """, arguments: [diagramUuid, pattern])
        let maxSuffix = existing
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .filter { (0...Self.maxMintedSuffix).contains($0) }
            .max() ?? 0
        return prefix + String(format: "%04d", maxSuffix + 1)
    }

    // MARK: - The single write path

    func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        guard !req.mutations.isEmpty else {
            throw StoreError.badRequest(detail: "batch-apply carried no mutations")
        }
        guard let diagram = try fetchDiagram(uuid: req.diagramUuid) else {
            throw StoreError.notFound(entity: "diagram", key: req.diagramUuid)
        }
        if let expected = req.expectedRevision, expected != diagram.revision {
            throw StoreError.revisionConflict(
                scopeUuid: diagram.uuid, expected: expected, actual: diagram.revision)
        }
        var ledger: [String: String] = [:]
        var results: [DiagramMutationResult] = []
        // Tracked so later mutations validate against POST-mutation state
        // (a promotion earlier in the batch changes the tier the next
        // diagramUpdate must see) and the event carries the final row.
        var currentDiagram = diagram
        var lastElementUuid: String?
        for (index, mutation) in req.mutations.enumerated() {
            switch mutation {
            case .elementAdd(let add):
                let result = try applyElementAdd(
                    diagram: currentDiagram, add: add, ledger: &ledger, index: index)
                results.append(result)
                lastElementUuid = result.uuid
            case .elementUpdate(let update):
                let result = try applyElementUpdate(
                    diagram: currentDiagram, update: update, index: index)
                results.append(result)
                lastElementUuid = result.uuid
            case .elementDelete(let delete):
                let result = try applyElementDelete(
                    diagram: currentDiagram, delete: delete, index: index)
                results.append(result)
                lastElementUuid = result.uuid
            case .diagramUpdate(let update):
                let result = try applyDiagramRowUpdate(
                    diagram: currentDiagram, update: update, index: index)
                results.append(result)
                guard let refreshed = try fetchDiagram(uuid: diagram.uuid) else {
                    throw StoreError.corruptState(
                        entity: "diagram", detail: "vanished mid-batch")
                }
                currentDiagram = refreshed
            }
        }
        let revision = try bumpDiagramRevision(diagramUuid: diagram.uuid)
        let action = req.mutations.count == 1
            ? req.mutations[0].kind : "batch_apply"
        // The event carries the FINAL row: a batch containing a promotion
        // must signal the NEW tier/session (and touch the new session),
        // or a GMVibes window filtering by session never sees a diagram
        // promoted into it. element_uuid is set only for a single ELEMENT
        // mutation — a lone diagram_update names no element.
        try recordDiagramChange(
            diagram: currentDiagram, action: action,
            elementUuid: req.mutations.count == 1 ? lastElementUuid : nil,
            mutationCount: req.mutations.count, revision: revision)
        return DiagramBatchApplyResponse(
            diagramUuid: diagram.uuid, revision: revision, results: results)
    }

    // MARK: - Per-mutation bodies (called ONLY from diagramBatchApply)

    private func applyElementAdd(
        diagram: DiagramRow, add: DiagramElementAdd,
        ledger: inout [String: String], index: Int
    ) throws -> DiagramMutationResult {
        let type = add.payload.elementType
        if add.parentElementUuid != nil, add.parentClientRef != nil {
            throw StoreError.badRequest(
                detail: "pass parentElementUuid OR parentClientRef, not both")
        }
        var parentUuid = add.parentElementUuid
        if let ref = add.parentClientRef {
            guard let resolved = ledger[ref] else {
                throw StoreError.badRequest(detail:
                    "parentClientRef '\(ref)' does not name an earlier elementAdd in this batch")
            }
            parentUuid = resolved
        }
        let parent = try parentUuid.map { try fetchElementInfo(uuid: $0) }
        try validateDiagramElementShape(
            diagramUuid: diagram.uuid, type: type, parent: parent, payload: add.payload)

        // Resolve a connector's second endpoint, which may name an element
        // created earlier in THIS batch — the exact parallel of
        // parentClientRef, and why the ref rides on the mutation rather than
        // inside the payload.
        var payload = DiagramStrokeCodec.normalizedForStorage(add.payload)
        if case .connector(let connector) = payload {
            if connector.targetElementUuid != nil, add.targetClientRef != nil {
                throw StoreError.badRequest(
                    detail: "pass targetElementUuid OR targetClientRef, not both")
            }
            var targetUuid = connector.targetElementUuid
            if let ref = add.targetClientRef {
                guard let resolved = ledger[ref] else {
                    throw StoreError.badRequest(detail:
                        "targetClientRef '\(ref)' does not name an earlier elementAdd in this batch")
                }
                targetUuid = resolved
            }
            if let targetUuid {
                try validateConnectorTarget(
                    diagramUuid: diagram.uuid, referrerUuid: "(new connector)",
                    parentOfReferrer: parentUuid, targetUuid: targetUuid)
                payload = .connector(ConnectorPayload(
                    targetElementUuid: targetUuid,
                    strokeColor: connector.strokeColor,
                    strokeWidth: connector.strokeWidth,
                    lineStyle: connector.lineStyle,
                    headKind: connector.headKind,
                    routingKind: connector.routingKind,
                    tailKind: connector.tailKind,
                    label: connector.label))
            }
        } else if add.targetClientRef != nil {
            throw StoreError.badRequest(
                detail: "targetClientRef is only meaningful for a connector element")
        }

        let code: String
        if let requested = add.code {
            try DopeCode.validateCode(requested, field: "element code")
            code = requested
        } else {
            code = try mintElementCode(diagramUuid: diagram.uuid, type: type)
        }
        if let description = add.description, description.count > 512 {
            throw StoreError.badRequest(detail: "element description exceeds 512 characters")
        }
        let sortOrder: Int
        if let requested = add.sortOrder {
            sortOrder = requested
        } else if let parentUuid {
            sortOrder = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sort_order), -1) + 1 FROM diagram_element
                WHERE parent_element_uuid = ?
                """, arguments: [parentUuid]) ?? 0
        } else {
            sortOrder = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sort_order), -1) + 1 FROM diagram_element
                WHERE diagram_uuid = ? AND parent_element_uuid IS NULL
                """, arguments: [diagram.uuid]) ?? 0
        }
        if let scale = add.scale, scale <= 0 {
            throw StoreError.badRequest(detail: "scale must be > 0")
        }

        let uuid = try core.insertBase(db, table: "diagram_element", extra: [
            "diagram_uuid": diagram.uuid,
            "parent_element_uuid": parentUuid,
            "element_type": type.rawValue,
            "code": code,
            "name": add.name ?? type.defaultName,
            "description": add.description ?? "",
            "sort_order": sortOrder,
            "center_x": add.centerX ?? 0,
            "center_y": add.centerY ?? 0,
            "element_z": add.elementZ ?? 0,
            "scale": add.scale ?? 1,
        ])
        try insertSubtypeRow(elementUuid: uuid, payload: payload)
        if let ref = add.clientRef { ledger[ref] = uuid }
        return DiagramMutationResult(
            index: index, kind: "element_add", clientRef: add.clientRef,
            uuid: uuid, version: 0)
    }

    private func applyElementUpdate(
        diagram: DiagramRow, update: DiagramElementUpdate, index: Int
    ) throws -> DiagramMutationResult {
        let info = try fetchElementInfo(uuid: update.elementUuid)
        guard info.diagramUuid == diagram.uuid else {
            throw StoreError.badRequest(detail:
                "element \(update.elementUuid) belongs to a different diagram")
        }

        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let code = update.code {
            try DopeCode.validateCode(code, field: "element code")
            set["code"] = code
        }
        if let name = update.name { set["name"] = name }
        if let description = update.description {
            guard description.count <= 512 else {
                throw StoreError.badRequest(detail: "element description exceeds 512 characters")
            }
            set["description"] = description
        }
        if let sortOrder = update.sortOrder { set["sort_order"] = sortOrder }
        if let centerX = update.centerX { set["center_x"] = centerX }
        if let centerY = update.centerY { set["center_y"] = centerY }
        if let elementZ = update.elementZ { set["element_z"] = elementZ }
        if let scale = update.scale {
            guard scale > 0 else { throw StoreError.badRequest(detail: "scale must be > 0") }
            set["scale"] = scale
        }
        if let newParent = update.parentElementUuid {
            guard newParent != info.uuid else {
                throw StoreError.badRequest(detail: "an element cannot parent itself")
            }
            set["parent_element_uuid"] = newParent
        }

        // Validate the FINAL (parent, payload) shape — reparent and payload
        // can change in one call.
        let finalParentUuid = update.parentElementUuid ?? info.parentElementUuid
        let finalParent = try finalParentUuid.map { try fetchElementInfo(uuid: $0) }
        let currentPayload = update.payload
        if let payload = currentPayload {
            try validateDiagramElementShape(
                diagramUuid: diagram.uuid, type: info.type,
                parent: finalParent, payload: payload)
        } else if update.parentElementUuid != nil {
            // Reparent without a payload still needs the containment check;
            // fabricate nothing — check the parent-type rule directly.
            let spec = DiagramElementTypeSpec.spec(for: info.type)
            guard let allowed = spec.allowedParentTypes else {
                throw StoreError.badRequest(detail:
                    "\(info.type.rawValue) is a top-level element type and cannot be reparented")
            }
            guard let finalParent, allowed.contains(finalParent.type) else {
                throw StoreError.badRequest(detail:
                    "a \(info.type.rawValue) cannot live under a "
                    + "\(finalParent?.type.rawValue ?? "missing parent") (legal: "
                    + allowed.map(\.rawValue).sorted().joined(separator: "/") + ")")
            }
            guard finalParent.diagramUuid == diagram.uuid else {
                throw StoreError.badRequest(detail:
                    "parent element \(finalParent.uuid) belongs to a different diagram")
            }
        }
        guard !set.isEmpty || update.payload != nil else {
            throw StoreError.emptyUpdate(entity: "diagram_element")
        }

        // updateBase with an empty set still bumps version + updated_at under
        // the optimistic-lock guard — exactly right for a payload-only edit
        // (the element row's version IS the aggregate lock).
        try core.updateBase(db, table: "diagram_element", uuid: info.uuid,
                            expectedVersion: update.expectedVersion, set: set)
        if let payload = update.payload {
            try replaceSubtypeRow(
                elementUuid: info.uuid,
                payload: DiagramStrokeCodec.normalizedForStorage(payload))
        }
        guard let version = try Int64.fetchOne(
            db, sql: "SELECT version FROM diagram_element WHERE uuid = ?", arguments: [info.uuid]
        ) else {
            throw StoreError.corruptState(entity: "diagram_element", detail: "vanished after update")
        }
        return DiagramMutationResult(index: index, kind: "element_update",
                                     uuid: info.uuid, version: version)
    }

    private func applyElementDelete(
        diagram: DiagramRow, delete: DiagramElementDelete, index: Int
    ) throws -> DiagramMutationResult {
        let info = try fetchElementInfo(uuid: delete.elementUuid)
        guard info.diagramUuid == diagram.uuid else {
            throw StoreError.badRequest(detail:
                "element \(delete.elementUuid) belongs to a different diagram")
        }
        // Nesting depth is exactly 2 (top-level + children), so the subtree
        // count is self + direct children.
        let children = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM diagram_element WHERE parent_element_uuid = ?",
            arguments: [info.uuid]) ?? 0
        // Plain CASCADE unwinds everything: children via the self-FK, subtype
        // rows via element_uuid, vertex rows via the subtype FKs. No RESTRICT
        // anywhere in the family.
        try core.deleteBase(db, table: "diagram_element", uuid: info.uuid,
                            expectedVersion: delete.expectedVersion)
        return DiagramMutationResult(index: index, kind: "element_delete",
                                     uuid: info.uuid, cascadedElements: children + 1)
    }

    private func applyDiagramRowUpdate(
        diagram: DiagramRow, update: DiagramRowUpdate, index: Int
    ) throws -> DiagramMutationResult {
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let code = update.code {
            try DopeCode.validateCode(code, field: "diagram code")
            set["code"] = code
        }
        if let name = update.name { set["name"] = name }
        if let description = update.description {
            guard description.count <= 512 else {
                throw StoreError.badRequest(detail: "diagram description exceeds 512 characters")
            }
            set["description"] = description
        }

        if let promotion = update.promotion {
            let owner: DiagramOwner
            switch promotion.tier {
            case .project:
                owner = try resolveDiagramOwner(
                    projectUuid: promotion.ownerUuid, instanceUuid: nil,
                    sessionUuid: nil, promptUuid: nil)
            case .session:
                owner = try resolveDiagramOwner(
                    projectUuid: nil, instanceUuid: nil,
                    sessionUuid: promotion.ownerUuid, promptUuid: nil)
            case .prompt:
                owner = try resolveDiagramOwner(
                    projectUuid: nil, instanceUuid: nil,
                    sessionUuid: nil, promptUuid: promotion.ownerUuid)
            }
            guard owner.projectUuid == diagram.projectUuid else {
                throw StoreError.badRequest(detail:
                    "promotion target resolves to a different project — a diagram never changes project")
            }
            // Same-code collision at the new tier would trip the partial
            // unique index mid-UPDATE; pre-check for the friendly message.
            let finalCode = update.code ?? diagram.code
            if try Row.fetchOne(db, sql: """
                SELECT uuid FROM diagram
                WHERE tier = ? AND \(owner.ownerColumn) = ? AND code = ? AND uuid != ?
                """, arguments: [owner.tier.rawValue, owner.ownerUuid, finalCode, diagram.uuid]
            ) != nil {
                throw StoreError.badRequest(detail:
                    "a diagram coded '\(finalCode)' already exists at the target tier")
            }
            set["tier"] = owner.tier.rawValue
            // updateValue, not subscript: typed-nil subscript assignment
            // REMOVES the key and the NULL-out silently vanishes (the
            // base_composable_uuid lesson).
            set.updateValue(owner.sessionUuid, forKey: "session_uuid")
            set.updateValue(owner.promptUuid, forKey: "prompt_uuid")
        }

        // gmcc_diagram_path is legal at EVERY tier since m0021. It used to
        // be refused at PROJECT because only an instance carried a checkout
        // to anchor against; screenshots now materialize under CKFS storage,
        // which a project has as much as a session does.
        if let patch = update.gmccDiagramPath {
            switch patch {
            case .set(let path):
                set["gmcc_diagram_path"] = path
            case .clear:
                set.updateValue(nil, forKey: "gmcc_diagram_path")
            }
        }

        if let visibility = update.visibility {
            set["visibility"] = visibility.rawValue
        }
        // The visibility/tier cross-guard, checked on the FINAL state so a
        // combined promote+set cannot sneak past it in either order: PUBLIC
        // is legal only on SESSION-tier rows (the dope write-repo gate — a
        // session resolves to exactly one instance root; other tiers do
        // not). Demote to PRIVATE first, or promote and stay PRIVATE.
        let finalTier = (set["tier"] as? String) ?? diagram.tier
        let finalVisibility = (set["visibility"] as? String) ?? diagram.visibility
        if finalVisibility == DiagramVisibility.public.rawValue,
           finalTier != DiagramTier.session.rawValue {
            throw StoreError.badRequest(detail:
                "PUBLIC visibility is legal only on SESSION-tier diagrams "
                + "(the repo serialization root comes from the session's "
                + "instance) — set --visibility PRIVATE first or keep the "
                + "diagram at SESSION tier")
        }

        guard !set.isEmpty else {
            throw StoreError.emptyUpdate(entity: "diagram")
        }
        try core.updateBase(db, table: "diagram", uuid: diagram.uuid,
                            expectedVersion: update.expectedVersion, set: set)
        guard let version = try Int64.fetchOne(
            db, sql: "SELECT version FROM diagram WHERE uuid = ?", arguments: [diagram.uuid]
        ) else {
            throw StoreError.corruptState(entity: "diagram", detail: "vanished after update")
        }
        return DiagramMutationResult(index: index, kind: "diagram_update",
                                     uuid: diagram.uuid, version: version)
    }

    // MARK: - Subtype persistence (whole-row insert / whole-row replace —
    // dispatched through the payload's own switch, so a sixth element type
    // cannot compile without a branch here)

    func insertSubtypeRow(
        elementUuid: String, payload: DiagramElementPayload
    ) throws {
        switch payload {
        case .drawingLayer(let p):
            _ = try core.insertBase(db, table: "diagram_drawing_layer", extra: [
                "element_uuid": elementUuid,
                "opacity": p.opacity,
                "visible": p.visible ? 1 : 0,
                "locked": p.locked ? 1 : 0,
            ])
        case .drawingStroke(let p):
            // Packed storage, per the spec's vertexStorage axis. The vertex
            // rows are deliberately NOT written for a stroke: one
            // representation at a time, so a read never has to decide which
            // of two disagreeing copies is true.
            _ = try core.insertBase(db, table: "diagram_drawing_stroke", extra: [
                "element_uuid": elementUuid,
                "tool": p.tool.rawValue,
                "stroke_color": p.strokeColor,
                "stroke_width": p.strokeWidth,
                "packed_vertices": DiagramStrokeCodec.pack(p.vertices),
                "vertex_count": p.vertices.count,
            ])
        case .drawingShape(let p):
            _ = try core.insertBase(db, table: "diagram_drawing_shape", extra: [
                "element_uuid": elementUuid,
                "shape_kind": p.shapeKind.rawValue,
                "stroke_color": p.strokeColor,
                "stroke_width": p.strokeWidth,
                "fill_color": p.fillColor,
                "corner_radius": p.cornerRadius,
            ])
            try replaceVertices(table: "diagram_shape_vertex",
                                parentColumn: "shape_element_uuid",
                                elementUuid: elementUuid, vertices: p.vertices,
                                withPressure: false)
        case .drawingText(let p):
            _ = try core.insertBase(db, table: "diagram_drawing_text", extra: [
                "element_uuid": elementUuid,
                "markdown": p.markdown,
                "width": p.width,
                "height": p.height,
                "font_size": p.fontSize,
                "text_color": p.textColor,
                "background_color": p.backgroundColor,
            ])
        case .connector(let p):
            _ = try core.insertBase(db, table: "diagram_connector", extra: [
                "element_uuid": elementUuid,
                "target_element_uuid": p.targetElementUuid,
                "stroke_color": p.strokeColor,
                "stroke_width": p.strokeWidth,
                "line_style": p.lineStyle.rawValue,
                "head_kind": p.headKind.rawValue,
                "routing_kind": p.routingKind.rawValue,
                "tail_kind": p.tailKind.rawValue,
                "label": p.label,
            ])
        case .umlNode(let p):
            _ = try core.insertBase(db, table: "diagram_uml_node", extra: [
                "element_uuid": elementUuid,
                "node_kind": p.nodeKind.rawValue,
                "width": p.width,
                "height": p.height,
                "markdown": p.markdown,
                "font_size": p.fontSize,
                "text_color": p.textColor,
                "stroke_color": p.strokeColor,
                "stroke_width": p.strokeWidth,
                "fill_color": p.fillColor,
            ])
        case .dopeScopePersistenceLayer(let p):
            _ = try core.insertBase(db, table: "diagram_dope_scope_persistence_layer", extra: [
                "element_uuid": elementUuid,
                "dope_scope_code": p.dopeScopeCode,
            ])
        case .dopeEntity(let p):
            _ = try core.insertBase(db, table: "diagram_dope_entity", extra: [
                "element_uuid": elementUuid,
                "entity_code": p.entityCode,
            ])
        }
    }

    /// Whole-row replacement: subtype rows are owned value rows (the element
    /// version is the aggregate lock), so a payload update rewrites every
    /// subtype column and the vertex set — no field patching, no clear flags.
    private func replaceSubtypeRow(
        elementUuid: String, payload: DiagramElementPayload
    ) throws {
        let now = Store.isoNow()
        func requireRow(_ table: String) throws {
            guard db.changesCount > 0 else {
                throw StoreError.corruptState(
                    entity: table, detail: "element \(elementUuid) has no subtype row")
            }
        }
        switch payload {
        case .drawingLayer(let p):
            try db.execute(sql: """
                UPDATE diagram_drawing_layer
                SET opacity = ?, visible = ?, locked = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.opacity, p.visible ? 1 : 0, p.locked ? 1 : 0,
                                 now, elementUuid])
            try requireRow("diagram_drawing_layer")
        case .drawingStroke(let p):
            try db.execute(sql: """
                UPDATE diagram_drawing_stroke
                SET tool = ?, stroke_color = ?, stroke_width = ?,
                    packed_vertices = ?, vertex_count = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.tool.rawValue, p.strokeColor, p.strokeWidth,
                                 DiagramStrokeCodec.pack(p.vertices), p.vertices.count,
                                 now, elementUuid])
            try requireRow("diagram_drawing_stroke")
            // Clear any legacy vertex rows: a stroke is packed-only, and a
            // leftover row set would be a second, silently disagreeing copy.
            try db.execute(sql: """
                DELETE FROM diagram_stroke_vertex WHERE stroke_element_uuid = ?
                """, arguments: [elementUuid])
        case .drawingShape(let p):
            try db.execute(sql: """
                UPDATE diagram_drawing_shape
                SET shape_kind = ?, stroke_color = ?, stroke_width = ?,
                    fill_color = ?, corner_radius = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.shapeKind.rawValue, p.strokeColor, p.strokeWidth,
                                 p.fillColor, p.cornerRadius, now, elementUuid])
            try requireRow("diagram_drawing_shape")
            try replaceVertices(table: "diagram_shape_vertex",
                                parentColumn: "shape_element_uuid",
                                elementUuid: elementUuid, vertices: p.vertices,
                                withPressure: false)
        case .drawingText(let p):
            try db.execute(sql: """
                UPDATE diagram_drawing_text
                SET markdown = ?, width = ?, height = ?, font_size = ?,
                    text_color = ?, background_color = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.markdown, p.width, p.height, p.fontSize,
                                 p.textColor, p.backgroundColor, now, elementUuid])
            try requireRow("diagram_drawing_text")
        case .connector(let p):
            try db.execute(sql: """
                UPDATE diagram_connector
                SET target_element_uuid = ?, stroke_color = ?, stroke_width = ?,
                    line_style = ?, head_kind = ?, routing_kind = ?, tail_kind = ?,
                    label = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.targetElementUuid, p.strokeColor, p.strokeWidth,
                                 p.lineStyle.rawValue, p.headKind.rawValue,
                                 p.routingKind.rawValue, p.tailKind.rawValue, p.label,
                                 now, elementUuid])
            try requireRow("diagram_connector")
        case .umlNode(let p):
            try db.execute(sql: """
                UPDATE diagram_uml_node
                SET node_kind = ?, width = ?, height = ?, markdown = ?,
                    font_size = ?, text_color = ?, stroke_color = ?,
                    stroke_width = ?, fill_color = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.nodeKind.rawValue, p.width, p.height, p.markdown,
                                 p.fontSize, p.textColor, p.strokeColor,
                                 p.strokeWidth, p.fillColor, now, elementUuid])
            try requireRow("diagram_uml_node")
        case .dopeScopePersistenceLayer(let p):
            try db.execute(sql: """
                UPDATE diagram_dope_scope_persistence_layer
                SET dope_scope_code = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.dopeScopeCode, now, elementUuid])
            try requireRow("diagram_dope_scope_persistence_layer")
        case .dopeEntity(let p):
            try db.execute(sql: """
                UPDATE diagram_dope_entity SET entity_code = ?, updated_at = ?
                WHERE element_uuid = ?
                """, arguments: [p.entityCode, now, elementUuid])
            try requireRow("diagram_dope_entity")
        }
    }

    /// Atomic whole-set vertex replacement: DELETE + ordered re-INSERT by
    /// seq, inside the caller's transaction. Fresh uuids every time — vertex
    /// rows are BaseEntity rows (user decision) but NOT stable identities.
    private func replaceVertices(
        table: String, parentColumn: String,
        elementUuid: String, vertices: [DiagramVertex], withPressure: Bool
    ) throws {
        try db.execute(sql: "DELETE FROM \(table) WHERE \(parentColumn) = ?",
                       arguments: [elementUuid])
        for (seq, vertex) in vertices.enumerated() {
            var extra: [String: (any DatabaseValueConvertible)?] = [
                parentColumn: elementUuid,
                "seq": seq,
                "x": vertex.x,
                "y": vertex.y,
            ]
            if withPressure { extra["pressure"] = vertex.pressure }
            _ = try core.insertBase(db, table: table, extra: extra)
        }
    }

}
