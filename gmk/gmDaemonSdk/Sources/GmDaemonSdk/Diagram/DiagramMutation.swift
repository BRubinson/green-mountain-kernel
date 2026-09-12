import Foundation

/// The batch currency. `applyDiagramMutations` is the ONLY mutation body in
/// the store — the granular DIAGRAM_NODE_* verbs are one-element batches
/// routed through the same code, so they structurally cannot drift from
/// batch semantics. Mutations apply strictly in array order inside one
/// transaction; any failure rolls back everything; the whole batch bumps
/// diagram.revision exactly once and emits exactly one DIAGRAM_CHANGE event.
///
/// Encoding: `{"kind": "<case>", "fields": {...}}` — the DiagramElementPayload
/// discipline (single-word tag keys, camelCase case-struct keys).
public enum DiagramMutation: Codable, Hashable, Sendable {
    case elementAdd(DiagramElementAdd)
    case elementUpdate(DiagramElementUpdate)
    case elementDelete(DiagramElementDelete)
    case diagramUpdate(DiagramRowUpdate)

    public var kind: String {
        switch self {
        case .elementAdd: return "element_add"
        case .elementUpdate: return "element_update"
        case .elementDelete: return "element_delete"
        case .diagramUpdate: return "diagram_update"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, fields }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "element_add":
            self = .elementAdd(try c.decode(DiagramElementAdd.self, forKey: .fields))
        case "element_update":
            self = .elementUpdate(try c.decode(DiagramElementUpdate.self, forKey: .fields))
        case "element_delete":
            self = .elementDelete(try c.decode(DiagramElementDelete.self, forKey: .fields))
        case "diagram_update":
            self = .diagramUpdate(try c.decode(DiagramRowUpdate.self, forKey: .fields))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown diagram mutation kind '\(kind)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .elementAdd(let m): try c.encode(m, forKey: .fields)
        case .elementUpdate(let m): try c.encode(m, forKey: .fields)
        case .elementDelete(let m): try c.encode(m, forKey: .fields)
        case .diagramUpdate(let m): try c.encode(m, forKey: .fields)
        }
    }
}

/// Add one element. The payload's tag IS the element type (no separate
/// discriminator to disagree with it). `clientRef` is an in-batch temp id:
/// a later mutation in the SAME batch may parent onto it via
/// `parentClientRef`, so one gesture can create a layer and its strokes
/// atomically. Omitted code/name are minted by the store (`stroke_0007`
/// style / the type's default name).
public struct DiagramElementAdd: Codable, Hashable, Sendable {
    public let clientRef: String?
    /// Exactly one of these for child types; both nil for top-level types.
    public let parentElementUuid: String?
    public let parentClientRef: String?
    /// In-batch temp id for a connector's TARGET, the exact parallel of
    /// `parentClientRef`: a connector can point at an element created
    /// earlier in the same batch, before that element has a real uuid.
    /// Resolution is a batch concern, which is why it rides on the mutation
    /// and not inside ConnectorPayload. Setting both this and the payload's
    /// `targetElementUuid` is refused.
    public let targetClientRef: String?
    public let code: String?
    public let name: String?
    public let description: String?
    public let sortOrder: Int?
    public let centerX: Double?
    public let centerY: Double?
    public let elementZ: Double?
    public let scale: Double?
    public let payload: DiagramElementPayload

    public init(
        clientRef: String? = nil,
        parentElementUuid: String? = nil,
        parentClientRef: String? = nil,
        targetClientRef: String? = nil,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        elementZ: Double? = nil,
        scale: Double? = nil,
        payload: DiagramElementPayload
    ) {
        self.clientRef = clientRef
        self.parentElementUuid = parentElementUuid
        self.parentClientRef = parentClientRef
        self.targetClientRef = targetClientRef
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.centerX = centerX
        self.centerY = centerY
        self.elementZ = elementZ
        self.scale = scale
        self.payload = payload
    }
}

/// Update one element. Base fields are a plain-optional patch (every base
/// column is NOT NULL, so nil-means-leave-alone needs no clear flags). A
/// present payload REPLACES the subtype row and vertex set wholesale and
/// must match the element's type (morphing refused). `parentElementUuid`
/// reparents a child element — unambiguous as a plain optional because a
/// child type's parent can never be NULL and a top-level type can never
/// have one.
public struct DiagramElementUpdate: Codable, Hashable, Sendable {
    public let elementUuid: String
    /// The element row's optimistic lock — THE aggregate lock for the whole
    /// element (subtype + vertices are owned value rows).
    public let expectedVersion: Int64
    public let code: String?
    public let name: String?
    public let description: String?
    public let sortOrder: Int?
    public let centerX: Double?
    public let centerY: Double?
    public let elementZ: Double?
    public let scale: Double?
    public let parentElementUuid: String?
    /// In-batch temp id for a connector's TARGET, the exact parallel of
    /// `parentClientRef`: a connector can point at an element created
    /// earlier in the same batch, before that element has a real uuid.
    /// Resolution is a batch concern, which is why it rides on the mutation
    /// and not inside ConnectorPayload. Setting both this and the payload's
    /// `targetElementUuid` is refused.
    public let targetClientRef: String?
    public let payload: DiagramElementPayload?

    public init(
        elementUuid: String,
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil,
        elementZ: Double? = nil,
        scale: Double? = nil,
        parentElementUuid: String? = nil,
        targetClientRef: String? = nil,
        payload: DiagramElementPayload? = nil
    ) {
        self.elementUuid = elementUuid
        self.expectedVersion = expectedVersion
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.centerX = centerX
        self.centerY = centerY
        self.elementZ = elementZ
        self.scale = scale
        self.parentElementUuid = parentElementUuid
        self.targetClientRef = targetClientRef
        self.payload = payload
    }
}

/// Delete one element and its subtree (plain CASCADE — the family has no
/// RESTRICT FKs and no external referrers).
public struct DiagramElementDelete: Codable, Hashable, Sendable {
    public let elementUuid: String
    public let expectedVersion: Int64

    public init(elementUuid: String, expectedVersion: Int64) {
        self.elementUuid = elementUuid
        self.expectedVersion = expectedVersion
    }
}

/// Update the diagram row itself: rename/describe, the one nullable base
/// column via FieldPatch, and tier promotion (an UPDATE that re-derives the
/// owner chain and NULLs the FKs below the new tier — the new owner must
/// resolve to the diagram's own project).
public struct DiagramRowUpdate: Codable, Hashable, Sendable {
    public let expectedVersion: Int64
    public let code: String?
    public let name: String?
    public let description: String?
    public let gmccDiagramPath: FieldPatch<String>?
    public let promotion: DiagramPromotion?
    /// v23: the visibility axis. PUBLIC is store-guarded to SESSION tier —
    /// the same session→instance-root gate dope write-repo uses.
    public let visibility: DiagramVisibility?

    public init(
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        gmccDiagramPath: FieldPatch<String>? = nil,
        promotion: DiagramPromotion? = nil,
        visibility: DiagramVisibility? = nil
    ) {
        self.expectedVersion = expectedVersion
        self.code = code
        self.name = name
        self.description = description
        self.gmccDiagramPath = gmccDiagramPath
        self.promotion = promotion
        self.visibility = visibility
    }
}

public struct DiagramPromotion: Codable, Hashable, Sendable {
    public let tier: DiagramTier
    /// The uuid of the row at the NEW tier that owns the diagram afterwards.
    public let ownerUuid: String

    public init(tier: DiagramTier, ownerUuid: String) {
        self.tier = tier
        self.ownerUuid = ownerUuid
    }
}

/// Per-mutation outcome, index-aligned with the request's mutations array.
public struct DiagramMutationResult: Codable, Hashable, Sendable {
    public let index: Int
    public let kind: String
    /// Echoed from an elementAdd so the client can map temp ids to real ones.
    public let clientRef: String?
    /// The affected row's uuid (the new element on add; absent for
    /// diagram_update, which the response's diagramUuid already names).
    public let uuid: String?
    /// The affected row's post-mutation optimistic-lock version.
    public let version: Int64?
    /// elementDelete only: how many element rows the subtree delete removed
    /// (including the target itself).
    public let cascadedElements: Int?

    public init(
        index: Int, kind: String, clientRef: String? = nil, uuid: String? = nil,
        version: Int64? = nil, cascadedElements: Int? = nil
    ) {
        self.index = index
        self.kind = kind
        self.clientRef = clientRef
        self.uuid = uuid
        self.version = version
        self.cascadedElements = cascadedElements
    }
}
