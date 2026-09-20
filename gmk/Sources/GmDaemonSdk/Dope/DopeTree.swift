import Foundation

/// The DOPED tree types. Each level's content fields are declared once as a
/// `*Body` struct; the wire node types here and the `.doped.json` document
/// types both FLATTEN the same body via hand-written Codable, so wire↔file
/// parity is structural. References inside bodies are dot-path CODES, never
/// uuids — the JSON uuid ban is an absent field, not a validation rule.
/// Every child-collection CodingKey here and in DopeDocument.swift is a single
/// word with no underscore: under the snake_case strategies an explicit
/// snake_case raw value stops matching and the field silently decodes to nil.

// MARK: - Bodies (one declaration per level)

struct DopeScopeBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String

    init(code: String, name: String, description: String) {
        self.code = code
        self.name = name
        self.description = description
    }
}

struct DopePersistenceBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int

    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

struct DopeEntityBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let entityType: String
    let description: String
    let sortOrder: Int
    let repoRepresentativeFile: String?
    /// `domain_code.entity_code` — the BASE_COMPOSABLE entity whose
    /// properties this entity composes. A pure lookup like enumRef: the
    /// base's properties are NEVER replicated onto this entity in the db or
    /// the JSON; consumers union them at render time.
    let baseComposableRef: String?

    init(
        code: String,
        name: String,
        entityType: String,
        description: String,
        sortOrder: Int,
        repoRepresentativeFile: String?,
        baseComposableRef: String?
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

struct DopePropertyBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let dataType: String
    let nullable: Bool
    let isUnique: Bool
    let autoIncrement: Bool?
    let textCharLimit: Int?
    /// `domain.enums.enum_code` — non-nil iff dataType == "enum".
    let enumRef: String?
    /// `domain.entity.property` — non-nil iff dataType == "relationship".
    let relationshipTargetRef: String?
    /// `domain.entity.property` — the BASE_COMPOSABLE property this one
    /// materializes. Provenance only: the row is real and FK-referenceable;
    /// the tag records where it came from. Orthogonal to dataType.
    let baseOriginRef: String?

    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        dataType: String,
        nullable: Bool,
        isUnique: Bool,
        autoIncrement: Bool?,
        textCharLimit: Int?,
        enumRef: String?,
        relationshipTargetRef: String?,
        baseOriginRef: String?
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

struct DopeEnumBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let repoRepresentativeFile: String?

    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        repoRepresentativeFile: String?
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.repoRepresentativeFile = repoRepresentativeFile
    }
}

struct DopeOptionBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int

    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

// MARK: - Identity (wire only — documents never carry it)

struct DopeNodeIdentity: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let createdAt: String
    let updatedAt: String
    /// Soft delete / whiteout. Lives HERE, on the wire-only identity layer,
    /// and deliberately NOT on the body: the body is what
    /// DopeProjection.documents emits, and a saved .doped.json represents
    /// REAL STATE only. A tombstone is a masking artifact — it is assumed
    /// absent from a base scope and rides only on the overlay tiers
    /// (PROJECT_ITEM / SESSION_INSTANCE_ITEM), which are db-only and never
    /// serialized. Keeping it off the body makes that structural rather than
    /// a rule someone has to remember.
    let deletedOn: String?

    init(
        uuid: String,
        version: Int64,
        createdAt: String,
        updatedAt: String,
        deletedOn: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedOn = deletedOn
    }

    /// Tolerant: neither field exists on a pre-m0012 peer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        version = try c.decode(Int64.self, forKey: .version)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deletedOn = try c.decodeIfPresent(String.self, forKey: .deletedOn)
    }
}

extension DopeScopeTree {
    /// The same scope with a different domain list — the resolver rebuilds
    /// the tree structurally and must not invent scope identity.
    func replacingDomains(_ domains: [DopePersistenceNode]) -> DopeScopeTree {
        DopeScopeTree(
            identity: identity,
            body: body,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            scopeType: scopeType,
            revision: revision,
            domains: domains
        )
    }

    /// A structurally valid empty tree, for the both-layers-absent case.
    static var empty: DopeScopeTree {
        DopeScopeTree(
            identity: DopeNodeIdentity(uuid: "", version: 0, createdAt: "", updatedAt: ""),
            body: DopeScopeBody(code: "", name: "", description: ""),
            sessionUuid: nil,
            promptUuid: nil,
            scopeType: DopeScopeType.sessionInstance.rawValue,
            revision: 0,
            domains: []
        )
    }
}

// MARK: - Wire nodes (identity + body + children, flattened)

struct DopeOptionNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopeOptionBody

    init(identity: DopeNodeIdentity, body: DopeOptionBody) {
        self.identity = identity
        self.body = body
    }

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeOptionBody(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
    }
}

struct DopeEnumNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopeEnumBody
    let options: [DopeOptionNode]

    private enum CodingKeys: String, CodingKey { case options }

    init(identity: DopeNodeIdentity, body: DopeEnumBody, options: [DopeOptionNode]) {
        self.identity = identity
        self.body = body
        self.options = options
    }

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEnumBody(from: decoder)
        options = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeOptionNode].self, forKey: .options)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(options, forKey: .options)
    }
}

struct DopePropertyNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopePropertyBody

    init(identity: DopeNodeIdentity, body: DopePropertyBody) {
        self.identity = identity
        self.body = body
    }

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePropertyBody(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
    }
}

struct DopeEntityNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopeEntityBody
    let properties: [DopePropertyNode]

    private enum CodingKeys: String, CodingKey { case properties }

    init(identity: DopeNodeIdentity, body: DopeEntityBody, properties: [DopePropertyNode]) {
        self.identity = identity
        self.body = body
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEntityBody(from: decoder)
        properties = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopePropertyNode].self, forKey: .properties)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(properties, forKey: .properties)
    }
}

struct DopePersistenceNode: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopePersistenceBody
    let entities: [DopeEntityNode]
    let enums: [DopeEnumNode]

    private enum CodingKeys: String, CodingKey { case entities, enums }

    init(
        identity: DopeNodeIdentity,
        body: DopePersistenceBody,
        entities: [DopeEntityNode],
        enums: [DopeEnumNode]
    ) {
        self.identity = identity
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entities = try c.decode([DopeEntityNode].self, forKey: .entities)
        enums = try c.decode([DopeEnumNode].self, forKey: .enums)
    }

    func encode(to encoder: Encoder) throws {
        try identity.encode(to: encoder)
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entities, forKey: .entities)
        try c.encode(enums, forKey: .enums)
    }
}

/// The full wire tree of one scope.
struct DopeScopeTree: Codable, Hashable, Sendable {
    let identity: DopeNodeIdentity
    let body: DopeScopeBody
    /// nil for the two project tiers (m0013). A project-tier tree has no
    /// session, and the repo/boot axis is session-only by construction.
    let sessionUuid: String?
    let promptUuid: String?
    let scopeType: String
    let revision: Int64
    let domains: [DopePersistenceNode]

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, scopeType, revision, domains
    }

    init(
        identity: DopeNodeIdentity,
        body: DopeScopeBody,
        sessionUuid: String?,
        promptUuid: String?,
        scopeType: String,
        revision: Int64,
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

    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeScopeBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid)
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        scopeType = try c.decode(String.self, forKey: .scopeType)
        revision = try c.decode(Int64.self, forKey: .revision)
        domains = try c.decode([DopePersistenceNode].self, forKey: .domains)
    }

    func encode(to encoder: Encoder) throws {
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
struct DopeTreeCounts: Codable, Hashable, Sendable {
    let domains: Int
    let entities: Int
    let properties: Int
    let enums: Int
    let options: Int

    init(domains: Int, entities: Int, properties: Int, enums: Int, options: Int) {
        self.domains = domains
        self.entities = entities
        self.properties = properties
        self.enums = enums
        self.options = options
    }
}
