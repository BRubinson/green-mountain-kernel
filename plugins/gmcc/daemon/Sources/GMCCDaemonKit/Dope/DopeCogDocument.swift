import Foundation

/// The on-disk form of one cog: `cogs/{code}/{code}.index.cog.doped.json`.
///
/// Hulls ship FLAT — there is no nested cog directory level yet, because no
/// nestable element type exists. A hull's PersistenceOwner children do NOT
/// get files or directories of their own: they collapse into the hull's
/// `links` block on write and expand back into sibling element rows on read.
///
///     { "code": "gm_daemon", "name": "GM Daemon",
///       "elements": [
///         { "code": "gm_daemon", "element_type": "Hull",
///           "primary_path": "plugins/gmcc/daemon",
///           "links": { "persistence_owners": ["doped", "agentics"] } } ] }
///
/// The collapse is deliberately lossy-but-canonical: a PersistenceOwner's
/// own name and description are dropped, because the descriptive material
/// belongs to the persistence domain it names, not to the link. Expansion
/// therefore mints them from the code, and `expand(collapse(x)) == x` only
/// holds when owners are created that way — which is why seeding goes
/// through the same synthesis the reader uses, and why there is a
/// fixed-point test.
public struct DopeCogDocument: Codable, Hashable, Sendable {
    public let body: DopeCogBody
    public let elements: [DopeCogElementDocument]

    private enum CodingKeys: String, CodingKey { case elements }

    public init(body: DopeCogBody, elements: [DopeCogElementDocument]) {
        self.body = body
        self.elements = elements
    }

    public init(from decoder: Decoder) throws {
        body = try DopeCogBody(from: decoder)
        elements = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeCogElementDocument].self, forKey: .elements)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elements, forKey: .elements)
    }
}

/// A cog's identity fields, uuid-free like every other `*Body`.
public struct DopeCogBody: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int

    public init(code: String, name: String, description: String, sortOrder: Int) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

/// One top-level element (today: always a Hull) plus its collapsed links.
public struct DopeCogElementDocument: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let description: String
    public let sortOrder: Int
    public let elementType: String
    public let primaryPath: String?
    public let dopeScopeCode: String?
    public let links: DopeCogLinks?

    public init(
        code: String, name: String, description: String, sortOrder: Int,
        elementType: String, primaryPath: String? = nil,
        dopeScopeCode: String? = nil, links: DopeCogLinks? = nil
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.elementType = elementType
        self.primaryPath = primaryPath
        self.dopeScopeCode = dopeScopeCode
        self.links = links
    }
}

/// Links may only live on a Hull. `persistence_owners` holds persistence
/// domain CODES — ghost-tolerant, resolved at read time: a code naming no
/// domain is a warning, never an error, matching the dope_scope_code
/// precedent.
public struct DopeCogLinks: Codable, Hashable, Sendable {
    public let persistenceOwners: [String]

    public init(persistenceOwners: [String]) {
        self.persistenceOwners = persistenceOwners
    }
}
