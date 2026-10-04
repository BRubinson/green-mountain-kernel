import Foundation

/// The DIAGRAM read tree. Identity reuses DopeNodeIdentity, and each node
/// carries the SAME tagged payload enum GMVibes sends back in mutations, so
/// the read and write currencies cannot drift. Child-collection CodingKeys
/// are single words — fixed points of the snake_case strategies, where an
/// explicit snake_case raw value would silently decode to nil.

/// The shared, always-present element columns.
struct DiagramElementBase: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    /// Position relative to the parent element's space (diagram space for
    /// top-level elements).
    let centerX: Double
    let centerY: Double
    /// Relative z among SIBLINGS only; global paint order is depth-first
    /// with an (elementZ, code) tie-break.
    let elementZ: Double
    /// Composes multiplicatively down the tree.
    let scale: Double

    /// Creates a diagram element base with positioning and layout properties.
    ///
    /// - Parameters:
    ///   - code: The element code identifier.
    ///   - name: The element name.
    ///   - description: The element description.
    ///   - sortOrder: The sort order among siblings.
    ///   - centerX: The x position in parent space.
    ///   - centerY: The y position in parent space.
    ///   - elementZ: The z position relative to siblings.
    ///   - scale: The multiplicative scale applied down the tree.
    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        centerX: Double,
        centerY: Double,
        elementZ: Double,
        scale: Double
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.centerX = centerX
        self.centerY = centerY
        self.elementZ = elementZ
        self.scale = scale
    }
}

struct DiagramElementNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let base: DiagramElementBase
    let payload: DiagramElementPayload
    let children: [DiagramElementNode]

    private enum CodingKeys: String, CodingKey { case payload, children }

    /// Creates a diagram element tree node.
    ///
    /// - Parameters:
    ///   - identity: The node's identity metadata.
    ///   - base: The base element properties.
    ///   - payload: The element's type-specific payload.
    ///   - children: The child nodes in the tree.
    init(
        identity: DopeNodeIdentity,
        base: DiagramElementBase,
        payload: DiagramElementPayload,
        children: [DiagramElementNode]
    ) {
        self.identity = identity
        self.base = base
        self.payload = payload
        self.children = children
    }

    /// Decodes a diagram element node from a decoder.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any error from the decoding process.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        base = try DiagramElementBase(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payload = try c.decode(DiagramElementPayload.self, forKey: .payload)
        children = try c.decode([DiagramElementNode].self, forKey: .children)
    }

    /// Encodes this diagram element node to an encoder.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error from the encoding process.
    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try base.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(payload, forKey: .payload)
        try c.encode(children, forKey: .children)
    }
}

/// The full read tree of one diagram: the row's fields + the nested
/// top-level elements (only dope_scope / drawing_layer may appear at the
/// top — validateDiagramElementShape's invariant, backstopped by schema).
struct DiagramTree: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let tier: String
    let projectUuid: String
    let instanceUuid: String?
    let sessionUuid: String?
    let promptUuid: String?
    let code: String
    let name: String
    let description: String
    let gmccDiagramPath: String?
    /// The whole-tree content counter.
    let revision: Int64
    let elements: [DiagramElementNode]

    private enum CodingKeys: String, CodingKey {
        case tier, projectUuid, instanceUuid, sessionUuid, promptUuid
        case code, name, description, gmccDiagramPath, revision, elements
    }

    /// Creates a diagram tree with all properties.
    ///
    /// - Parameters:
    ///   - identity: The diagram's identity metadata.
    ///   - tier: The diagram tier classification.
    ///   - projectUuid: The project UUID, or `nil` for non-project diagrams.
    ///   - instanceUuid: The instance UUID, or `nil` if not project-scoped.
    ///   - sessionUuid: The session UUID, or `nil` if not session-scoped.
    ///   - promptUuid: The prompt UUID, or `nil` if not prompt-scoped.
    ///   - code: The diagram code.
    ///   - name: The diagram name.
    ///   - description: The diagram description.
    ///   - gmccDiagramPath: The GMCC diagram file path, or `nil` if not persisted.
    ///   - revision: The content revision counter.
    ///   - elements: The top-level element nodes.
    init(
        identity: DopeNodeIdentity,
        tier: String,
        projectUuid: String,
        instanceUuid: String?,
        sessionUuid: String?,
        promptUuid: String?,
        code: String,
        name: String,
        description: String,
        gmccDiagramPath: String?,
        revision: Int64,
        elements: [DiagramElementNode]
    ) {
        self.identity = identity
        self.tier = tier
        self.projectUuid = projectUuid
        self.instanceUuid = instanceUuid
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.gmccDiagramPath = gmccDiagramPath
        self.revision = revision
        self.elements = elements
    }

    /// Decodes a diagram tree from a decoder.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any error from the decoding process.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier = try c.decode(String.self, forKey: .tier)
        projectUuid = try c.decode(String.self, forKey: .projectUuid)
        instanceUuid = try c.decodeIfPresent(String.self, forKey: .instanceUuid)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid)
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        gmccDiagramPath = try c.decodeIfPresent(String.self, forKey: .gmccDiagramPath)
        revision = try c.decode(Int64.self, forKey: .revision)
        elements = try c.decode([DiagramElementNode].self, forKey: .elements)
    }

    /// Encodes this diagram tree to an encoder.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any error from the encoding process.
    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tier, forKey: .tier)
        try c.encode(projectUuid, forKey: .projectUuid)
        try c.encodeIfPresent(instanceUuid, forKey: .instanceUuid)
        try c.encodeIfPresent(sessionUuid, forKey: .sessionUuid)
        try c.encodeIfPresent(promptUuid, forKey: .promptUuid)
        try c.encode(code, forKey: .code)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(gmccDiagramPath, forKey: .gmccDiagramPath)
        try c.encode(revision, forKey: .revision)
        try c.encode(elements, forKey: .elements)
    }
}

/// Read-time resolution of one dope_scope binding element, computed through
/// the EXISTING dopeScopeCandidates ladder against the diagram row's own
/// session/prompt FKs.
///
/// `resolvedVia` nil ⇒ the legal `.absent` ghost state
/// (always the case for PROJECT/INSTANCE-tier diagrams, which carry no
/// session context). Entity-level presence is the render pass's job — it
/// holds the hydrated dope tree this row points at.
struct DiagramBindingResolution: Codable, Hashable, Sendable {
    let elementUuid: String
    let dopeScopeCode: String
    /// "prompt" | "session_base" | nil (absent).
    let resolvedVia: String?
    let scopeUuid: String?
    let dopeRevision: Int64?

    /// Creates a diagram binding resolution.
    ///
    /// - Parameters:
    ///   - elementUuid: The UUID of the element being resolved.
    ///   - dopeScopeCode: The dope scope code for the binding.
    ///   - resolvedVia: The resolution path ("prompt", "session_base", or `nil`).
    ///   - scopeUuid: The UUID of the resolved scope, or `nil` if unresolved.
    ///   - dopeRevision: The dope revision, or `nil` if unresolved.
    init(
        elementUuid: String,
        dopeScopeCode: String,
        resolvedVia: String?,
        scopeUuid: String?,
        dopeRevision: Int64?
    ) {
        self.elementUuid = elementUuid
        self.dopeScopeCode = dopeScopeCode
        self.resolvedVia = resolvedVia
        self.scopeUuid = scopeUuid
        self.dopeRevision = dopeRevision
    }

    private enum CodingKeys: String, CodingKey {
        case elementUuid, dopeScopeCode, resolvedVia, scopeUuid, dopeRevision
    }

    /// Decodes a diagram binding resolution from a decoder.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any error from the decoding process.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elementUuid = try c.decode(String.self, forKey: .elementUuid)
        dopeScopeCode = try c.decode(String.self, forKey: .dopeScopeCode)
        resolvedVia = try c.decodeIfPresent(String.self, forKey: .resolvedVia)
        scopeUuid = try c.decodeIfPresent(String.self, forKey: .scopeUuid)
        dopeRevision = try c.decodeIfPresent(Int64.self, forKey: .dopeRevision)
    }
}
