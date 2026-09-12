import Foundation

/// The DOPED tree types. Each level's content fields are declared exactly
/// once as a `*Body` struct; the wire node types (here) and the `.doped.json`
/// document types (DopeDocument.swift) both FLATTEN the same body into their
/// own JSON object via hand-written Codable, so a field cannot land on one
/// side only — wire↔file parity is structural, not maintained.
///
/// CONSTRAINT: every child-collection CodingKey in this file and in
/// DopeDocument.swift is a single word with no underscore (`domains`,
/// `entities`, `enums`, `options`, `properties`). Under the snake_case
/// strategies an explicit snake_case raw value stops matching and the field
/// silently decodes to nil (see Envelope.swift) — single-word keys are fixed
/// points of both strategies.
///
/// References inside bodies are dot-path CODES (`domain.entity.property`,
/// `domain.enums.enum_code`), never uuids: uuids exist only in
/// `DopeNodeIdentity`, which the document types simply do not include — the
/// JSON uuid ban is an absent field, not a validation rule.

// MARK: - Bodies (one declaration per level)

public struct DopeScopeBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String

    public init(code: String, name: String, description: String) {
        self.code = code
        self.name = name
        self.description = description
    }
}

public struct DopePersistenceBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int

    public init(code: String, name: String, description: String, sortOrder: Int
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

public struct DopeEntityBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let entityType: String
    public let description: String
    public let sortOrder: Int
    public let repoRepresentativeFile: String?
    /// `domain_code.entity_code` — the BASE_COMPOSABLE entity whose
    /// properties this entity composes. A pure lookup like enumRef: the
    /// base's properties are NEVER replicated onto this entity in the db or
    /// the JSON; consumers union them at render time.
    public let baseComposableRef: String?

    public init(
        code: String, name: String, entityType: String, description: String,
        sortOrder: Int, repoRepresentativeFile: String?, baseComposableRef: String?
    ) {
        self.code = code
        self.name = name
        self.entityType = entityType
        self.description = description
        self.sortOrder = sortOrder
        self.repoRepresentativeFile = repoRepresentativeFile
        self.baseComposableRef = baseComposableRef
    }
}

public struct DopePropertyBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    public let dataType: String
    public let nullable: Bool
    public let isUnique: Bool
    public let autoIncrement: Bool?
    public let textCharLimit: Int?
    /// `domain.enums.enum_code` — non-nil iff dataType == "enum".
    public let enumRef: String?
    /// `domain.entity.property` — non-nil iff dataType == "relationship".
    public let relationshipTargetRef: String?
    /// `domain.entity.property` — the BASE_COMPOSABLE property this one
    /// materializes. Provenance only: the row is real and FK-referenceable;
    /// the tag records where it came from. Orthogonal to dataType.
    public let baseOriginRef: String?

    public init(
        code: String, name: String, description: String, sortOrder: Int,
        dataType: String, nullable: Bool, isUnique: Bool,
        autoIncrement: Bool?, textCharLimit: Int?,
        enumRef: String?, relationshipTargetRef: String?, baseOriginRef: String?
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.dataType = dataType
        self.nullable = nullable
        self.isUnique = isUnique
        self.autoIncrement = autoIncrement
        self.textCharLimit = textCharLimit
        self.enumRef = enumRef
        self.relationshipTargetRef = relationshipTargetRef
        self.baseOriginRef = baseOriginRef
    }
}

public struct DopeEnumBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    public let repoRepresentativeFile: String?

    public init(
        code: String, name: String, description: String, sortOrder: Int,
        repoRepresentativeFile: String?
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.repoRepresentativeFile = repoRepresentativeFile
    }
}

public struct DopeOptionBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int

    public init(code: String, name: String, description: String, sortOrder: Int
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

// MARK: - Identity (wire only — documents never carry it)

public struct DopeNodeIdentity: Codable, Hashable, Sendable {
    public let uuid: String
    public let version: Int64
    public let createdAt: String
    public let updatedAt: String
    /// Soft delete / whiteout. Lives HERE, on the wire-only identity layer,
    /// and deliberately NOT on the body: the body is what
    /// DopeProjection.documents emits, and a saved .doped.json represents
    /// REAL STATE only. A tombstone is a masking artifact — it is assumed
    /// absent from a base scope and rides only on the overlay tiers
    /// (PROJECT_ITEM / SESSION_INSTANCE_ITEM), which are db-only and never
    /// serialized. Keeping it off the body makes that structural rather than
    /// a rule someone has to remember.
    public let deletedOn: String?

    public init(
        uuid: String, version: Int64, createdAt: String, updatedAt: String,
        deletedOn: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedOn = deletedOn
    }

    /// Tolerant: neither field exists on a pre-m0012 peer.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        version = try c.decode(Int64.self, forKey: .version)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedOn = try c.decodeIfPresent(String.self, forKey: .deletedOn)
    }
}

public extension DopeScopeTree {
    /// The same scope with a different domain list — the resolver rebuilds
    /// the tree structurally and must not invent scope identity.
    func replacingDomains(_ domains: [DopePersistenceNode]) -> DopeScopeTree {
        DopeScopeTree(identity: identity, body: body, sessionUuid: sessionUuid,
                      promptUuid: promptUuid, scopeType: scopeType,
                      revision: revision, domains: domains)
    }

    /// A structurally valid empty tree, for the both-layers-absent case.
    static var empty: DopeScopeTree {
        DopeScopeTree(
            identity: DopeNodeIdentity(uuid: "", version: 0, createdAt: "", updatedAt: ""),
            body: DopeScopeBody(code: "", name: "", description: ""),
            sessionUuid: nil, promptUuid: nil,
            scopeType: DopeScopeType.sessionInstance.rawValue, revision: 0, domains: [])
    }
}

// MARK: - Wire nodes (identity + body + children, flattened)

public struct DopeOptionNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopeOptionBody

    public init(identity: DopeNodeIdentity, body: DopeOptionBody) {
        self.identity = identity
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeOptionBody(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
    }
}

public struct DopeEnumNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopeEnumBody
    public let options: [DopeOptionNode]

    private enum CodingKeys: String, CodingKey { case options }

    public init(identity: DopeNodeIdentity, body: DopeEnumBody, options: [DopeOptionNode]) {
        self.identity = identity
        self.body = body
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEnumBody(from: decoder)
        options = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeOptionNode].self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(options, forKey: .options)
    }
}

public struct DopePropertyNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopePropertyBody

    public init(identity: DopeNodeIdentity, body: DopePropertyBody) {
        self.identity = identity
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePropertyBody(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
    }
}

public struct DopeEntityNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopeEntityBody
    public let properties: [DopePropertyNode]

    private enum CodingKeys: String, CodingKey { case properties }

    public init(identity: DopeNodeIdentity, body: DopeEntityBody, properties: [DopePropertyNode]) {
        self.identity = identity
        self.body = body
        self.properties = properties
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEntityBody(from: decoder)
        properties = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopePropertyNode].self, forKey: .properties)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(properties, forKey: .properties)
    }
}

public struct DopePersistenceNode: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopePersistenceBody
    public let entities: [DopeEntityNode]
    public let enums: [DopeEnumNode]

    private enum CodingKeys: String, CodingKey { case entities, enums }

    public init(
        identity: DopeNodeIdentity, body: DopePersistenceBody,
        entities: [DopeEntityNode], enums: [DopeEnumNode]
    ) {
        self.identity = identity
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entities = try c.decode([DopeEntityNode].self, forKey: .entities)
        enums = try c.decode([DopeEnumNode].self, forKey: .enums)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entities, forKey: .entities)
        try c.encode(enums, forKey: .enums)
    }
}

/// The full wire tree of one scope.
public struct DopeScopeTree: Codable, Hashable, Sendable {
    public let identity: DopeNodeIdentity
    public let body: DopeScopeBody
    /// nil for the two project tiers (m0013). A project-tier tree has no
    /// session, and the repo/boot axis is session-only by construction.
    public let sessionUuid: String?
    public let promptUuid: String?
    public let scopeType: String
    public let revision: Int64
    public let domains: [DopePersistenceNode]

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, scopeType, revision, domains
    }

    public init(
        identity: DopeNodeIdentity, body: DopeScopeBody, sessionUuid: String?,
        promptUuid: String?, scopeType: String, revision: Int64,
        domains: [DopePersistenceNode]
    ) {
        self.identity = identity
        self.body = body
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.scopeType = scopeType
        self.revision = revision
        self.domains = domains
    }

    public init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeScopeBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid)
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        scopeType = try c.decode(String.self, forKey: .scopeType)
        revision = try c.decode(Int64.self, forKey: .revision)
        domains = try c.decode([DopePersistenceNode].self, forKey: .domains)
    }

    public func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sessionUuid, forKey: .sessionUuid)
        try c.encodeIfPresent(promptUuid, forKey: .promptUuid)
        try c.encode(scopeType, forKey: .scopeType)
        try c.encode(revision, forKey: .revision)
        try c.encode(domains, forKey: .domains)
    }
}

/// Cascade accounting returned by node deletions.
public struct DopeTreeCounts: Codable, Hashable, Sendable {
    public let domains: Int
    public let entities: Int
    public let properties: Int
    public let enums: Int
    public let options: Int

    public init(domains: Int, entities: Int, properties: Int, enums: Int, options: Int) {
        self.domains = domains
        self.entities = entities
        self.properties = properties
        self.enums = enums
        self.options = options
    }
}
