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

    /// Creates a scope body with code, name and description.
    /// - Parameters:
    ///   - code: The scope identifier.
    ///   - name: The human-readable scope name.
    ///   - description: A summary of the scope's purpose.
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

    /// Creates a persistence domain body with code, name, description and sort order.
    /// - Parameters:
    ///   - code: The domain identifier.
    ///   - name: The human-readable domain name.
    ///   - description: A summary of the domain's purpose.
    ///   - sortOrder: The ordering index within the scope.
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
    /// `domain_code.entity_code` — the BASE_COMPOSABLE entity whose properties this entity composes.
    ///
    /// A pure lookup like enumRef: the base's properties are NEVER replicated
    /// onto this entity in the db or the JSON; consumers union them at render
    /// time.
    let baseComposableRef: String?

    /// Creates an entity body with all properties.
    /// - Parameters:
    ///   - code: The entity identifier.
    ///   - name: The human-readable entity name.
    ///   - entityType: The entity classification.
    ///   - description: A summary of the entity's purpose.
    ///   - sortOrder: The ordering index within the domain.
    ///   - repoRepresentativeFile: Path to the source file, if any.
    ///   - baseComposableRef: The base composable entity reference, if inherited.
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
    /// `domain.entity.property` — the BASE_COMPOSABLE property this one materializes.
    ///
    /// Provenance only: the row is real and FK-referenceable; the tag records
    /// where it came from. Orthogonal to dataType.
    let baseOriginRef: String?

    /// Creates a property body with all properties.
    /// - Parameters:
    ///   - code: The property identifier.
    ///   - name: The human-readable property name.
    ///   - description: A summary of the property's purpose.
    ///   - sortOrder: The ordering index within the entity.
    ///   - dataType: The data type classification.
    ///   - nullable: Whether the property allows nil.
    ///   - isUnique: Whether the property is unique.
    ///   - autoIncrement: Whether the property auto-increments, if applicable.
    ///   - textCharLimit: Character limit for text properties, if any.
    ///   - enumRef: The enum reference if `dataType` is "enum".
    ///   - relationshipTargetRef: The relationship target if `dataType` is "relationship".
    ///   - baseOriginRef: The base composable property reference, if inherited.
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

    /// Creates an enum body with code, name, description and sort order.
    /// - Parameters:
    ///   - code: The enum identifier.
    ///   - name: The human-readable enum name.
    ///   - description: A summary of the enum's purpose.
    ///   - sortOrder: The ordering index within the domain.
    ///   - repoRepresentativeFile: Path to the source file, if any.
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

    /// Creates an enum option body with code, name, description and sort order.
    /// - Parameters:
    ///   - code: The option identifier.
    ///   - name: The human-readable option name.
    ///   - description: A summary of the option's purpose.
    ///   - sortOrder: The ordering index within the enum.
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
    /// Soft delete / whiteout.
    ///
    /// Wire-only identity layer, NOT on the body (body is what
    /// DopeProjection.documents emits). A tombstone is a masking artifact on
    /// overlay tiers (PROJECT_ITEM / SESSION_INSTANCE_ITEM), which are db-only.
    /// Keeping it off the body makes that structural.
    let deletedOn: String?

    /// Creates a dope node identity with version metadata.
    /// - Parameters:
    ///   - uuid: The unique identifier for this node.
    ///   - version: The version number of this node.
    ///   - createdAt: The timestamp when this node was created.
    ///   - updatedAt: The timestamp when this node was last updated.
    ///   - deletedOn: The timestamp when this node was deleted, or nil if active.
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

    /// Decodes a dope node identity from a decoder, tolerant of pre-m0012 peers.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
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
    /// Returns a new scope tree with different domains.
    ///
    /// The resolver rebuilds the tree structurally and must not invent scope
    /// identity. All other fields of the scope remain unchanged.
    /// - Parameter domains: The new domain list for this scope.
    /// - Returns: A new `DopeScopeTree` with the same identity and body but different domains.
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

    /// Creates an enum option node with identity and body.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The option's content fields.
    init(identity: DopeNodeIdentity, body: DopeOptionBody) {
        self.identity = identity
        self.body = body
    }

    /// Decodes an enum option node from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeOptionBody(from: decoder)
    }

    /// Encodes an enum option node to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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

    /// Creates an enum node with identity, body and options.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The enum's content fields.
    ///   - options: The list of options in this enum.
    init(identity: DopeNodeIdentity, body: DopeEnumBody, options: [DopeOptionNode]) {
        self.identity = identity
        self.body = body
        self.options = options
    }

    /// Decodes an enum node from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEnumBody(from: decoder)
        options = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeOptionNode].self, forKey: .options)
    }

    /// Encodes an enum node to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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

    /// Creates an entity property node with identity and body.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The property's content fields.
    init(identity: DopeNodeIdentity, body: DopePropertyBody) {
        self.identity = identity
        self.body = body
    }

    /// Decodes an entity property node from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePropertyBody(from: decoder)
    }

    /// Encodes an entity property node to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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

    /// Creates an entity node with identity, body and properties.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The entity's content fields.
    ///   - properties: The list of properties in this entity.
    init(identity: DopeNodeIdentity, body: DopeEntityBody, properties: [DopePropertyNode]) {
        self.identity = identity
        self.body = body
        self.properties = properties
    }

    /// Decodes an entity node from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopeEntityBody(from: decoder)
        properties = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopePropertyNode].self, forKey: .properties)
    }

    /// Encodes an entity node to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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

    /// Creates a persistence domain node with identity, body, entities and enums.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The domain's content fields.
    ///   - entities: The list of entities in this domain.
    ///   - enums: The list of enums in this domain.
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

    /// Decodes a persistence domain node from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
    init(from decoder: Decoder) throws {
        identity = try DopeNodeIdentity(from: decoder)
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entities = try c.decode([DopeEntityNode].self, forKey: .entities)
        enums = try c.decode([DopeEnumNode].self, forKey: .enums)
    }

    /// Encodes a persistence domain node to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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
    /// nil for the two project tiers (m0013).
    ///
    /// A project-tier tree has no session, and the repo/boot axis is
    /// session-only by construction.
    let sessionUuid: String?
    let promptUuid: String?
    let scopeType: String
    let revision: Int64
    let domains: [DopePersistenceNode]

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, scopeType, revision, domains
    }

    /// Creates a scope tree with identity, body and all metadata.
    /// - Parameters:
    ///   - identity: The node's version metadata and identity.
    ///   - body: The scope's content fields.
    ///   - sessionUuid: The session UUID, nil for project-tier scopes.
    ///   - promptUuid: The prompt UUID if this scope belongs to a prompt.
    ///   - scopeType: The classification of this scope.
    ///   - revision: The revision number of this tree.
    ///   - domains: The list of persistence domains in this scope.
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

    /// Decodes a scope tree from a decoder.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Any decoding error from the decoder.
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

    /// Encodes a scope tree to an encoder.
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Any encoding error from the encoder.
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

    /// Creates cascade counts with deletion accounting.
    /// - Parameters:
    ///   - domains: Number of domains affected.
    ///   - entities: Number of entities affected.
    ///   - properties: Number of properties affected.
    ///   - enums: Number of enums affected.
    ///   - options: Number of options affected.
    init(domains: Int, entities: Int, properties: Int, enums: Int, options: Int) {
        self.domains = domains
        self.entities = entities
        self.properties = properties
        self.enums = enums
        self.options = options
    }
}
