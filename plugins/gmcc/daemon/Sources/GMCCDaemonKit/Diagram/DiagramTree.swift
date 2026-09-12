import Foundation

/// The DIAGRAM read tree. Identity reuses DopeNodeIdentity (a generic
/// uuid/version/timestamp quad — the mirror-don't-share decision is scoped
/// to the level machinery, not to plain value shapes). Each node carries the
/// SAME tagged payload enum GMVibes sends back in mutations, so the read and
/// write currencies cannot drift.
///
/// CodingKey constraint (see DopeTree.swift): child-collection keys are
/// single words (`elements`, `children`, `payload`) — fixed points of the
/// snake_case strategies; bare-case multiword keys convert normally.

/// The shared, always-present element columns.
public struct DiagramElementBase: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    /// Position relative to the parent element's space (diagram space for
    /// top-level elements).
    public let centerX: Double
    public let centerY: Double
    /// Relative z among SIBLINGS only; global paint order is depth-first
    /// with an (elementZ, code) tie-break.
    public let elementZ: Double
    /// Composes multiplicatively down the tree.
    public let scale: Double

    public init(
        code: String, name: String, description: String, sortOrder: Int,
        centerX: Double, centerY: Double, elementZ: Double, scale: Double
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

public struct DiagramElementNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let base: DiagramElementBase
    public let payload: DiagramElementPayload
    public let children: [DiagramElementNode]

    private enum CodingKeys: String, CodingKey { case payload, children }

    public init(
        identity: DopeNodeIdentity, base: DiagramElementBase,
        payload: DiagramElementPayload, children: [DiagramElementNode]
    ) {
        self.identity = identity
        self.base = base
        self.payload = payload
        self.children = children
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        base = try DiagramElementBase(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payload = try c.decode(DiagramElementPayload.self, forKey: .payload)
        children = try c.decode([DiagramElementNode].self, forKey: .children)
    }

    public func encode(to encoder: Encoder) throws {
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
public struct DiagramTree: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let tier: String
    public let projectUuid: String
    public let instanceUuid: String?
    public let sessionUuid: String?
    public let promptUuid: String?
    public let code: String
    public let name: String
    public let description: String
    public let gmccDiagramPath: String?
    /// The whole-tree content counter.
    public let revision: Int64
    public let elements: [DiagramElementNode]

    private enum CodingKeys: String, CodingKey {
        case tier, projectUuid, instanceUuid, sessionUuid, promptUuid
        case code, name, description, gmccDiagramPath, revision, elements
    }

    public init(
        identity: DopeNodeIdentity, tier: String, projectUuid: String,
        instanceUuid: String?, sessionUuid: String?, promptUuid: String?,
        code: String, name: String, description: String,
        gmccDiagramPath: String?, revision: Int64, elements: [DiagramElementNode]
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
/// session/prompt FKs. `resolvedVia` nil ⇒ the legal `.absent` ghost state
/// (always the case for PROJECT/INSTANCE-tier diagrams, which carry no
/// session context). Entity-level presence is the render pass's job — it
/// holds the hydrated dope tree this row points at.
public struct DiagramBindingResolution: Codable, Hashable, Sendable {
    public let elementUuid: String
    public let dopeScopeCode: String
    /// "prompt" | "session_base" | nil (absent).
    public let resolvedVia: String?
    public let scopeUuid: String?
    public let dopeRevision: Int64?

    public init(
        elementUuid: String, dopeScopeCode: String, resolvedVia: String?,
        scopeUuid: String?, dopeRevision: Int64?
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elementUuid = try c.decode(String.self, forKey: .elementUuid)
        dopeScopeCode = try c.decode(String.self, forKey: .dopeScopeCode)
        resolvedVia = try c.decodeIfPresent(String.self, forKey: .resolvedVia)
        scopeUuid = try c.decodeIfPresent(String.self, forKey: .scopeUuid)
        dopeRevision = try c.decodeIfPresent(Int64.self, forKey: .dopeRevision)
    }
}
