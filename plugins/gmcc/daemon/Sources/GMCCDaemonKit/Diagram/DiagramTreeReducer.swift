import Foundation

/// The pure, in-memory implementation of `applyDiagramMutations` — the
/// SECOND implementation of the daemon's one write path, kit-resident so it
/// can never silently drift from `Store+Diagram.swift`: the parity test runs
/// identical batches through both and asserts identical trees. GMVibes'
/// non-persisted viewer commits through this (a ~20-line `DiagramCommitting`
/// wrapper); switching persistence on later is one conformer swap, not a
/// semantics change.
///
/// Semantics mirrored from the store, in order: whole-batch expectedRevision
/// CAS; strict array order; all-or-nothing (throwing leaves the input tree
/// untouched — value semantics make rollback free); in-batch clientRef →
/// uuid ledger (`parentClientRef` resolves only to EARLIER adds); payload
/// tag = element type; `DiagramElementTypeSpec` containment; code
/// validation + `prefix_%04d` minting (max numeric suffix + 1, absurd
/// suffixes ignored); per-element expectedVersion CAS; a present payload
/// replaces the subtype wholesale; subtree-cascade delete; exactly ONE
/// `revision + 1` for the whole batch.

/// Uuid/timestamp injection so tests are deterministic and the app supplies
/// real `UUID()`s.
public protocol DiagramIdentityMinting {
    func mintUuid() -> String
    func now() -> String
}

/// Counter-based deterministic minting (tests, previews).
public final class SequentialDiagramMinting: DiagramIdentityMinting {
    private var counter = 0
    private let prefix: String
    private let timestamp: String

    public init(prefix: String = "local", timestamp: String = "t") {
        self.prefix = prefix
        self.timestamp = timestamp
    }

    public func mintUuid() -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    public func now() -> String { timestamp }
}

public enum DiagramReducerError: Error, Equatable, Sendable {
    case revisionConflict(expected: Int64, actual: Int64)
    case versionConflict(elementUuid: String, expected: Int64, actual: Int64)
    case notFound(elementUuid: String)
    case badRequest(detail: String)
    case emptyUpdate(elementUuid: String)
}

public enum DiagramTreeReducer {

    static let maxMintedSuffix = 999_999

    public static func apply(
        _ mutations: [DiagramMutation], to tree: DiagramTree,
        expectedRevision: Int64? = nil,
        minting: some DiagramIdentityMinting
    ) throws -> DiagramTree {
        guard !mutations.isEmpty else {
            throw DiagramReducerError.badRequest(detail: "batch-apply carried no mutations")
        }
        if let expected = expectedRevision, expected != tree.revision {
            throw DiagramReducerError.revisionConflict(expected: expected,
                                                       actual: tree.revision)
        }

        var elements = tree.elements
        var row = RowState(tree: tree)
        var ledger: [String: String] = [:]

        for mutation in mutations {
            switch mutation {
            case .elementAdd(let add):
                try applyAdd(add, elements: &elements, ledger: &ledger, minting: minting)
            case .elementUpdate(let update):
                try applyUpdate(update, elements: &elements, minting: minting)
            case .elementDelete(let delete):
                try applyDelete(delete, elements: &elements)
            case .diagramUpdate(let update):
                try applyRowUpdate(update, row: &row, minting: minting)
            }
        }

        return DiagramTree(
            identity: DopeNodeIdentity(uuid: tree.identity.uuid,
                                       version: row.version,
                                       createdAt: tree.identity.createdAt,
                                       updatedAt: row.updatedAt),
            tier: tree.tier, projectUuid: tree.projectUuid,
            instanceUuid: tree.instanceUuid, sessionUuid: tree.sessionUuid,
            promptUuid: tree.promptUuid, code: row.code, name: row.name,
            description: row.description, gmccDiagramPath: row.gmccDiagramPath,
            revision: tree.revision + 1,
            elements: normalized(elements))
    }

    // MARK: - Diagram row state

    private struct RowState {
        var version: Int64
        var updatedAt: String
        var code: String
        var name: String
        var description: String
        var gmccDiagramPath: String?

        init(tree: DiagramTree) {
            version = tree.identity.version
            updatedAt = tree.identity.updatedAt
            code = tree.code
            name = tree.name
            description = tree.description
            gmccDiagramPath = tree.gmccDiagramPath
        }
    }

    // MARK: - element_add

    private static func applyAdd(
        _ add: DiagramElementAdd, elements: inout [DiagramElementNode],
        ledger: inout [String: String], minting: some DiagramIdentityMinting
    ) throws {
        let type = add.payload.elementType
        if add.parentElementUuid != nil, add.parentClientRef != nil {
            throw DiagramReducerError.badRequest(
                detail: "pass parentElementUuid OR parentClientRef, not both")
        }
        var parentUuid = add.parentElementUuid
        if let ref = add.parentClientRef {
            guard let resolved = ledger[ref] else {
                throw DiagramReducerError.badRequest(detail:
                    "parentClientRef '\(ref)' does not name an earlier elementAdd in this batch")
            }
            parentUuid = resolved
        }
        let parentType = try parentUuid.map { uuid -> DiagramElementType in
            guard let node = findNode(uuid, in: elements) else {
                throw DiagramReducerError.notFound(elementUuid: uuid)
            }
            return node.payload.elementType
        }
        try validateShape(type: type, parentType: parentType, payload: add.payload)

        // Resolve the connector's second endpoint, which may name an element
        // created earlier in THIS batch — the exact parallel of
        // parentClientRef, and the reason the ref rides on the mutation
        // rather than inside the payload.
        var payload = DiagramStrokeCodec.normalizedForStorage(add.payload)
        if case .connector(let connector) = payload {
            if connector.targetElementUuid != nil, add.targetClientRef != nil {
                throw DiagramReducerError.badRequest(
                    detail: "pass targetElementUuid OR targetClientRef, not both")
            }
            var targetUuid = connector.targetElementUuid
            if let ref = add.targetClientRef {
                guard let resolved = ledger[ref] else {
                    throw DiagramReducerError.badRequest(detail:
                        "targetClientRef '\(ref)' does not name an earlier elementAdd in this batch")
                }
                targetUuid = resolved
            }
            if let targetUuid {
                // The referrer's own uuid is minted below, so self-reference
                // is impossible here by construction; the rest of the rule
                // still needs checking.
                try validateConnectorTarget(
                    referrerUuid: "(new connector)", parentOfReferrer: parentUuid,
                    targetUuid: targetUuid, elements: elements)
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
            throw DiagramReducerError.badRequest(
                detail: "targetClientRef is only meaningful for a connector element")
        }

        let code: String
        if let requested = add.code {
            try mapValidation { try DopeCode.validateCode(requested, field: "element code") }
            code = requested
        } else {
            code = mintCode(type: type, elements: elements)
        }
        if let description = add.description, description.count > 512 {
            throw DiagramReducerError.badRequest(detail: "element description exceeds 512 characters")
        }
        if let scale = add.scale, scale <= 0 {
            throw DiagramReducerError.badRequest(detail: "scale must be > 0")
        }
        let siblings = parentUuid.map { uuid in
            findNode(uuid, in: elements)?.children ?? []
        } ?? elements
        let sortOrder = add.sortOrder
            ?? ((siblings.map(\.base.sortOrder).max() ?? -1) + 1)

        let now = minting.now()
        let node = DiagramElementNode(
            identity: DopeNodeIdentity(uuid: minting.mintUuid(), version: 0,
                                       createdAt: now, updatedAt: now),
            base: DiagramElementBase(
                code: code, name: add.name ?? type.defaultName,
                description: add.description ?? "", sortOrder: sortOrder,
                centerX: add.centerX ?? 0, centerY: add.centerY ?? 0,
                elementZ: add.elementZ ?? 0, scale: add.scale ?? 1),
            payload: payload, children: [])

        if let parentUuid {
            guard insertChild(node, under: parentUuid, in: &elements) else {
                throw DiagramReducerError.notFound(elementUuid: parentUuid)
            }
        } else {
            elements.append(node)
        }
        if let ref = add.clientRef { ledger[ref] = node.identity.uuid }
    }

    // MARK: - element_update

    private static func applyUpdate(
        _ update: DiagramElementUpdate, elements: inout [DiagramElementNode],
        minting: some DiagramIdentityMinting
    ) throws {
        guard let node = findNode(update.elementUuid, in: elements) else {
            throw DiagramReducerError.notFound(elementUuid: update.elementUuid)
        }
        guard node.identity.version == update.expectedVersion else {
            throw DiagramReducerError.versionConflict(
                elementUuid: update.elementUuid,
                expected: update.expectedVersion, actual: node.identity.version)
        }
        let type = node.payload.elementType
        if let code = update.code {
            try mapValidation { try DopeCode.validateCode(code, field: "element code") }
        }
        if let description = update.description, description.count > 512 {
            throw DiagramReducerError.badRequest(detail: "element description exceeds 512 characters")
        }
        if let scale = update.scale, scale <= 0 {
            throw DiagramReducerError.badRequest(detail: "scale must be > 0")
        }
        if let newParent = update.parentElementUuid, newParent == update.elementUuid {
            throw DiagramReducerError.badRequest(detail: "an element cannot parent itself")
        }
        let hasBasePatch = update.code != nil || update.name != nil
            || update.description != nil || update.sortOrder != nil
            || update.centerX != nil || update.centerY != nil
            || update.elementZ != nil || update.scale != nil
            || update.parentElementUuid != nil
        guard hasBasePatch || update.payload != nil else {
            throw DiagramReducerError.emptyUpdate(elementUuid: update.elementUuid)
        }
        if let payload = update.payload {
            guard payload.elementType == type else {
                throw DiagramReducerError.badRequest(detail:
                    "payload kind '\(payload.elementType.rawValue)' does not match element type '\(type.rawValue)' — type morphing is refused")
            }
        }

        // Validate the FINAL parent shape when reparenting or replacing payload.
        let currentParentUuid = findParentUuid(of: update.elementUuid, in: elements)
        let finalParentUuid = update.parentElementUuid ?? currentParentUuid
        let finalParentType = finalParentUuid.flatMap { findNode($0, in: elements)?.payload.elementType }
        if update.payload != nil || update.parentElementUuid != nil {
            if update.parentElementUuid != nil, finalParentType == nil {
                throw DiagramReducerError.notFound(elementUuid: update.parentElementUuid!)
            }
            try validateShape(type: type, parentType: finalParentType,
                              payload: update.payload ?? node.payload)
        }

        // Detach when reparenting, then rewrite in place.
        var detached: DiagramElementNode?
        if let newParent = update.parentElementUuid, newParent != currentParentUuid {
            detached = removeNode(update.elementUuid, in: &elements)
            guard var moving = detached else {
                throw DiagramReducerError.notFound(elementUuid: update.elementUuid)
            }
            moving = rewritten(moving, update: update, minting: minting)
            guard insertChild(moving, under: newParent, in: &elements) else {
                throw DiagramReducerError.notFound(elementUuid: newParent)
            }
            return
        }
        _ = rewriteNode(update.elementUuid, in: &elements) { existing in
            rewritten(existing, update: update, minting: minting)
        }
    }

    private static func rewritten(
        _ node: DiagramElementNode, update: DiagramElementUpdate,
        minting: some DiagramIdentityMinting
    ) -> DiagramElementNode {
        DiagramElementNode(
            identity: DopeNodeIdentity(uuid: node.identity.uuid,
                                       version: node.identity.version + 1,
                                       createdAt: node.identity.createdAt,
                                       updatedAt: minting.now()),
            base: DiagramElementBase(
                code: update.code ?? node.base.code,
                name: update.name ?? node.base.name,
                description: update.description ?? node.base.description,
                sortOrder: update.sortOrder ?? node.base.sortOrder,
                centerX: update.centerX ?? node.base.centerX,
                centerY: update.centerY ?? node.base.centerY,
                elementZ: update.elementZ ?? node.base.elementZ,
                scale: update.scale ?? node.base.scale),
            payload: update.payload.map(DiagramStrokeCodec.normalizedForStorage)
                ?? node.payload,
            children: node.children)
    }

    // MARK: - element_delete

    private static func applyDelete(
        _ delete: DiagramElementDelete, elements: inout [DiagramElementNode]
    ) throws {
        guard let node = findNode(delete.elementUuid, in: elements) else {
            throw DiagramReducerError.notFound(elementUuid: delete.elementUuid)
        }
        guard node.identity.version == delete.expectedVersion else {
            throw DiagramReducerError.versionConflict(
                elementUuid: delete.elementUuid,
                expected: delete.expectedVersion, actual: node.identity.version)
        }
        _ = removeNode(delete.elementUuid, in: &elements)
    }

    // MARK: - diagram_update

    private static func applyRowUpdate(
        _ update: DiagramRowUpdate, row: inout RowState,
        minting: some DiagramIdentityMinting
    ) throws {
        guard row.version == update.expectedVersion else {
            throw DiagramReducerError.versionConflict(
                elementUuid: "diagram", expected: update.expectedVersion,
                actual: row.version)
        }
        guard update.promotion == nil else {
            throw DiagramReducerError.badRequest(
                detail: "tier promotion is not supported by the local reducer")
        }
        if let code = update.code {
            try mapValidation { try DopeCode.validateCode(code, field: "diagram code") }
            row.code = code
        }
        if let name = update.name { row.name = name }
        if let description = update.description { row.description = description }
        if let patch = update.gmccDiagramPath {
            switch patch {
            case .set(let value): row.gmccDiagramPath = value
            case .clear: row.gmccDiagramPath = nil
            }
        }
        row.version += 1
        row.updatedAt = minting.now()
    }

    // MARK: - Shape validation (mirrors validateDiagramElementShape)

    private static func validateShape(
        type: DiagramElementType, parentType: DiagramElementType?,
        payload: DiagramElementPayload
    ) throws {
        let spec = DiagramElementTypeSpec.spec(for: type)
        if let allowed = spec.allowedParentTypes {
            guard let parentType else {
                throw DiagramReducerError.badRequest(detail:
                    "\(type.rawValue) elements need a parent element ("
                    + allowed.map(\.rawValue).sorted().joined(separator: "/") + ")")
            }
            guard allowed.contains(parentType) else {
                throw DiagramReducerError.badRequest(detail:
                    "a \(type.rawValue) cannot live under a \(parentType.rawValue) (legal: "
                    + allowed.map(\.rawValue).sorted().joined(separator: "/") + ")")
            }
        } else if parentType != nil {
            throw DiagramReducerError.badRequest(detail:
                "\(type.rawValue) is a top-level element type and cannot have a parent")
        }
        switch payload {
        case .dopeScopePersistenceLayer(let p):
            try mapValidation {
                try DopeCode.validateCode(p.dopeScopeCode, field: "dope_scope binding code")
            }
        case .dopeEntity(let p):
            try mapValidation {
                _ = try DopeCode.parseEntityRef(p.entityCode, field: "dope entity binding")
            }
        case .drawingStroke(let p):
            if !p.vertices.isEmpty, p.vertices.count < 2 {
                throw DiagramReducerError.badRequest(
                    detail: "a stroke needs at least 2 vertices (or none)")
            }
        case .drawingShape(let p):
            if p.cornerRadius != nil, p.shapeKind != .rectangle {
                throw DiagramReducerError.badRequest(
                    detail: "corner_radius is only legal on rectangles")
            }
        case .drawingText(let p):
            guard p.width > 0, p.height > 0 else {
                throw DiagramReducerError.badRequest(
                    detail: "a text box needs a positive width and height")
            }
            guard p.fontSize > 0 else {
                throw DiagramReducerError.badRequest(
                    detail: "a text box needs a positive font size")
            }
        case .umlNode(let p):
            guard p.width > 0, p.height > 0 else {
                throw DiagramReducerError.badRequest(
                    detail: "a uml node needs a positive width and height")
            }
            if let fontSize = p.fontSize, fontSize <= 0 {
                throw DiagramReducerError.badRequest(
                    detail: "a uml node's font size must be positive when set")
            }
            if let strokeWidth = p.strokeWidth, strokeWidth <= 0 {
                throw DiagramReducerError.badRequest(
                    detail: "a uml node's stroke width must be positive when set")
            }
        case .connector(let p):
            guard p.strokeWidth > 0 else {
                throw DiagramReducerError.badRequest(
                    detail: "a connector needs a positive stroke width")
            }
            // The endpoint's CONTAINMENT rule is not checkable here: it
            // needs the target's parentage, which is tree context this
            // payload-only pass does not have. validateConnectorTarget below
            // is where it lands, called with the tree in hand.
            _ = p.targetElementUuid
        case .drawingLayer:
            break
        }
    }

    /// The connector containment rule, evaluated against the in-memory tree.
    ///
    /// The daemon answers the same question with SQL lookups; both call
    /// DiagramContainment so the RULE cannot drift even though the lookups
    /// do. This is the half of the parity contract a fixture alone would not
    /// guarantee.
    private static func validateConnectorTarget(
        referrerUuid: String, parentOfReferrer: String?,
        targetUuid: String, elements: [DiagramElementNode]
    ) throws {
        let spec = DiagramElementTypeSpec.spec(for: .connector)
        guard let ref = spec.elementRefs.first else { return }
        let grandparent = parentOfReferrer.flatMap {
            findParentUuid(of: $0, in: elements)
        }
        let targetExists = findNode(targetUuid, in: elements) != nil
        if let violation = DiagramContainment.validateReference(
            rule: ref.rule,
            referrerUuid: referrerUuid,
            parentOfReferrer: parentOfReferrer,
            grandparentOfReferrer: grandparent,
            targetUuid: targetUuid,
            parentOfTarget: findParentUuid(of: targetUuid, in: elements),
            targetExists: targetExists
        ) {
            throw DiagramReducerError.badRequest(
                detail: violation.message(role: "connector \(ref.role)",
                                          referrer: referrerUuid, target: targetUuid))
        }
    }

    private static func mapValidation(_ body: () throws -> Void) throws {
        do { try body() } catch {
            throw DiagramReducerError.badRequest(detail: String(describing: error))
        }
    }

    // MARK: - Code minting (mirrors mintElementCode)

    private static func mintCode(type: DiagramElementType,
                                 elements: [DiagramElementNode]) -> String {
        let prefix = type.codePrefix + "_"
        var maxSuffix = 0
        func walk(_ nodes: [DiagramElementNode]) {
            for node in nodes {
                if node.base.code.hasPrefix(prefix),
                   let suffix = Int(node.base.code.dropFirst(prefix.count)),
                   (0...maxMintedSuffix).contains(suffix) {
                    maxSuffix = max(maxSuffix, suffix)
                }
                walk(node.children)
            }
        }
        walk(elements)
        return prefix + String(format: "%04d", maxSuffix + 1)
    }

    // MARK: - Tree surgery helpers

    /// Depth-first lookup — public because hosts resolve hit uuids back to
    /// tree nodes with it (the drag path's node snapshot).
    public static func findNode(_ uuid: String, in elements: [DiagramElementNode]) -> DiagramElementNode? {
        for node in elements {
            if node.identity.uuid == uuid { return node }
            if let found = findNode(uuid, in: node.children) { return found }
        }
        return nil
    }

    private static func findParentUuid(of uuid: String,
                                       in elements: [DiagramElementNode]) -> String? {
        func walk(_ nodes: [DiagramElementNode], parent: String?) -> String? {
            for node in nodes {
                if node.identity.uuid == uuid { return parent }
                if let found = walk(node.children, parent: node.identity.uuid) { return found }
            }
            return nil
        }
        return walk(elements, parent: nil)
    }

    @discardableResult
    private static func removeNode(_ uuid: String,
                                   in elements: inout [DiagramElementNode]) -> DiagramElementNode? {
        if let index = elements.firstIndex(where: { $0.identity.uuid == uuid }) {
            return elements.remove(at: index)
        }
        for index in elements.indices {
            var children = elements[index].children
            if let removed = removeNode(uuid, in: &children) {
                elements[index] = withChildren(elements[index], children)
                return removed
            }
        }
        return nil
    }

    private static func insertChild(_ node: DiagramElementNode, under parentUuid: String,
                                    in elements: inout [DiagramElementNode]) -> Bool {
        for index in elements.indices {
            if elements[index].identity.uuid == parentUuid {
                elements[index] = withChildren(elements[index],
                                               elements[index].children + [node])
                return true
            }
            var children = elements[index].children
            if insertChild(node, under: parentUuid, in: &children) {
                elements[index] = withChildren(elements[index], children)
                return true
            }
        }
        return false
    }

    private static func rewriteNode(
        _ uuid: String, in elements: inout [DiagramElementNode],
        transform: (DiagramElementNode) -> DiagramElementNode
    ) -> Bool {
        for index in elements.indices {
            if elements[index].identity.uuid == uuid {
                elements[index] = transform(elements[index])
                return true
            }
            var children = elements[index].children
            if rewriteNode(uuid, in: &children, transform: transform) {
                elements[index] = withChildren(elements[index], children)
                return true
            }
        }
        return false
    }

    private static func withChildren(_ node: DiagramElementNode,
                                     _ children: [DiagramElementNode]) -> DiagramElementNode {
        DiagramElementNode(identity: node.identity, base: node.base,
                           payload: node.payload, children: children)
    }

    /// The store reads children `ORDER BY element_z, sort_order, code` —
    /// normalize the same way so reducer output and a daemon read tree
    /// compare equal in the parity test.
    private static func normalized(_ elements: [DiagramElementNode]) -> [DiagramElementNode] {
        elements
            .map { withChildren($0, normalized($0.children)) }
            .sorted { a, b in
                if a.base.elementZ != b.base.elementZ { return a.base.elementZ < b.base.elementZ }
                if a.base.sortOrder != b.base.sortOrder { return a.base.sortOrder < b.base.sortOrder }
                return a.base.code < b.base.code
            }
    }
}
