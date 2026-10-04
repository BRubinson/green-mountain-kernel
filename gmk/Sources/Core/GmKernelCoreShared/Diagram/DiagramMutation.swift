import Foundation

/// The batch currency.
///
/// `applyDiagramMutations` is the ONLY mutation body in the store; granular
/// DIAGRAM_NODE_* verbs are one-element batches through the same code. Mutations
/// apply strictly in array order inside one transaction; any failure rolls back
/// everything. The whole batch bumps diagram.revision once and emits one
/// DIAGRAM_CHANGE event.
enum DiagramMutation: Codable, Hashable, Sendable {
    case elementAdd(DiagramElementAdd)
    case elementUpdate(DiagramElementUpdate)
    case elementDelete(DiagramElementDelete)
    case diagramUpdate(DiagramRowUpdate)

    var kind: String {
        switch self {
        case .elementAdd: return "element_add"
        case .elementUpdate: return "element_update"
        case .elementDelete: return "element_delete"
        case .diagramUpdate: return "diagram_update"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, fields }

    /// Decodes a diagram mutation from a keyed container.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the kind is unknown.
    init(from decoder: Decoder) throws {
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
                forKey: .kind,
                in: c,
                debugDescription: "unknown diagram mutation kind '\(kind)'"
            )
        }
    }

    /// Encodes the diagram mutation to a keyed container.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
    func encode(to encoder: Encoder) throws {
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

/// Add one element.
///
/// The payload's tag IS the element type (no separate discriminator to disagree
/// with it). `clientRef` is an in-batch temp id: a later mutation in the SAME
/// batch may parent onto it via `parentClientRef`, so one gesture can create a
/// layer and its strokes atomically. Omitted code/name are minted by the store
/// (`stroke_0007` style / the type's default name).
struct DiagramElementAdd: Codable, Hashable, Sendable {
    let clientRef: String?
    /// Exactly one of these for child types; both nil for top-level types.
    let parentElementUuid: String?
    let parentClientRef: String?
    /// In-batch temp id for a connector's TARGET, the exact parallel of
    /// `parentClientRef`.
    ///
    /// A connector can point at an element created earlier in the same batch,
    /// before that element has a real uuid. Resolution is a batch concern; it
    /// rides on the mutation, not inside ConnectorPayload. Setting both this
    /// and the payload's `targetElementUuid` is refused.
    let targetClientRef: String?
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let centerX: Double?
    let centerY: Double?
    let elementZ: Double?
    let scale: Double?
    let payload: DiagramElementPayload

    /// Creates a diagram element addition mutation.
    ///
    /// - Parameters:
    ///   - payload: The element's typed payload.
    ///   - clientRef: In-batch temp id, or nil.
    ///   - parentElementUuid: The parent's uuid, or nil for top-level.
    ///   - parentClientRef: The parent's temp id if created in the same batch.
    ///   - targetClientRef: The target's temp id for connectors.
    ///   - code: Custom element code, or nil to auto-mint.
    ///   - name: Custom element name, or nil for type default.
    ///   - description: Optional description.
    ///   - sortOrder: Optional sort order.
    ///   - centerX: Optional x-coordinate.
    ///   - centerY: Optional y-coordinate.
    ///   - elementZ: Optional z-index.
    ///   - scale: Optional scale factor.
    init(
        payload: DiagramElementPayload,
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
        scale: Double? = nil
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

/// Update one element.
///
/// Base fields are a plain-optional patch (every base column is NOT NULL, so
/// nil-means-leave-alone needs no clear flags). A present payload REPLACES the
/// subtype row and vertex set wholesale and must match the element's type
/// (morphing refused). `parentElementUuid` reparents a child element —
/// unambiguous as a plain optional because a child type's parent can never be
/// NULL and a top-level type can never have one.
struct DiagramElementUpdate: Codable, Hashable, Sendable {
    let elementUuid: String
    /// The element row's optimistic lock — THE aggregate lock for the whole
    /// element (subtype + vertices are owned value rows).
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let centerX: Double?
    let centerY: Double?
    let elementZ: Double?
    let scale: Double?
    let parentElementUuid: String?
    /// In-batch temp id for a connector's TARGET, the exact parallel of
    /// `parentClientRef`.
    ///
    /// A connector can point at an element created earlier in the same batch,
    /// before that element has a real uuid. Resolution is a batch concern; it
    /// rides on the mutation, not inside ConnectorPayload. Setting both this
    /// and the payload's `targetElementUuid` is refused.
    let targetClientRef: String?
    let payload: DiagramElementPayload?

    /// Creates a diagram element update mutation.
    ///
    /// - Parameters:
    ///   - elementUuid: The element to update.
    ///   - expectedVersion: The version the caller last read.
    ///   - code: New custom code, or nil to leave unchanged.
    ///   - name: New custom name, or nil to leave unchanged.
    ///   - description: New description, or nil to leave unchanged.
    ///   - sortOrder: New sort order, or nil to leave unchanged.
    ///   - centerX: New x-coordinate, or nil to leave unchanged.
    ///   - centerY: New y-coordinate, or nil to leave unchanged.
    ///   - elementZ: New z-index, or nil to leave unchanged.
    ///   - scale: New scale factor, or nil to leave unchanged.
    ///   - parentElementUuid: New parent uuid, or nil to leave unchanged.
    ///   - targetClientRef: New target temp id for connectors, or nil.
    ///   - payload: New payload, or nil to leave unchanged.
    init(
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
struct DiagramElementDelete: Codable, Hashable, Sendable {
    let elementUuid: String
    let expectedVersion: Int64

    /// Creates a diagram element deletion mutation.
    ///
    /// - Parameters:
    ///   - elementUuid: The element to delete.
    ///   - expectedVersion: The version the caller last read.
    init(elementUuid: String, expectedVersion: Int64) {
        self.elementUuid = elementUuid
        self.expectedVersion = expectedVersion
    }
}

/// Update the diagram row itself: rename/describe, the one nullable base
/// column via FieldPatch, and tier promotion (an UPDATE that re-derives the
/// owner chain and NULLs the FKs below the new tier — the new owner must
/// resolve to the diagram's own project).
struct DiagramRowUpdate: Codable, Hashable, Sendable {
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let gmccDiagramPath: FieldPatch<String>?
    let promotion: DiagramPromotion?
    /// v23: the visibility axis.
    ///
    /// PUBLIC is store-guarded to SESSION tier — the same session→instance-root
    /// gate dope write-repo uses.
    let visibility: DiagramVisibility?

    /// Creates a diagram row update mutation.
    ///
    /// - Parameters:
    ///   - expectedVersion: The version the caller last read.
    ///   - code: New diagram code, or nil to leave unchanged.
    ///   - name: New diagram name, or nil to leave unchanged.
    ///   - description: New description, or nil to leave unchanged.
    ///   - gmccDiagramPath: Path patch, or nil to leave unchanged.
    ///   - promotion: Tier promotion details, or nil.
    ///   - visibility: New visibility level, or nil to leave unchanged.
    init(
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

struct DiagramPromotion: Codable, Hashable, Sendable {
    let tier: DiagramTier
    /// The uuid of the row at the NEW tier that owns the diagram afterwards.
    let ownerUuid: String

    /// Creates a diagram promotion request.
    ///
    /// - Parameters:
    ///   - tier: The new owner tier.
    ///   - ownerUuid: The uuid of the new owner at that tier.
    init(tier: DiagramTier, ownerUuid: String) {
        self.tier = tier
        self.ownerUuid = ownerUuid
    }
}

/// Per-mutation outcome, index-aligned with the request's mutations array.
struct DiagramMutationResult: Codable, Hashable, Sendable {
    let index: Int
    let kind: String
    /// Echoed from an elementAdd so the client can map temp ids to real ones.
    let clientRef: String?
    /// The affected row's uuid (the new element on add; absent for
    /// diagram_update, which the response's diagramUuid already names).
    let uuid: String?
    /// The affected row's post-mutation optimistic-lock version.
    let version: Int64?
    /// elementDelete only: how many element rows the subtree delete removed
    /// (including the target itself).
    let cascadedElements: Int?

    /// Creates a diagram mutation result.
    ///
    /// - Parameters:
    ///   - index: The index in the request's mutations array.
    ///   - kind: The mutation kind that was applied.
    ///   - clientRef: Echoed from elementAdd to map temp ids to real ones.
    ///   - uuid: The affected row's uuid, or nil for diagram_update.
    ///   - version: The post-mutation optimistic-lock version.
    ///   - cascadedElements: For elementDelete, count of rows deleted including target.
    init(
        index: Int,
        kind: String,
        clientRef: String? = nil,
        uuid: String? = nil,
        version: Int64? = nil,
        cascadedElements: Int? = nil
    ) {
        self.index = index
        self.kind = kind
        self.clientRef = clientRef
        self.uuid = uuid
        self.version = version
        self.cascadedElements = cascadedElements
    }
}
