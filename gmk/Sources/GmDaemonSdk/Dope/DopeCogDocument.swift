import Foundation

/// The on-disk form of one cog: `cogs/{code}/{code}.index.cog.doped.json`.
///
/// Hulls ship FLAT. A hull's PersistenceOwner children get no files of their
/// own: they collapse into the hull's `links` block on write and expand back
/// into sibling element rows on read. The collapse drops an owner's own name
/// and description, so `expand(collapse(x)) == x` holds only where owners are
/// synthesized from the code — seeding must go through the same synthesis the
/// reader uses.
struct DopeCogDocument: Codable, Hashable, Sendable {
    let body: DopeCogBody
    let elements: [DopeCogElementDocument]

    private enum CodingKeys: String, CodingKey { case elements }

    init(body: DopeCogBody, elements: [DopeCogElementDocument]) {
        self.body = body
        self.elements = elements
    }

    init(from decoder: Decoder) throws {
        body = try DopeCogBody(from: decoder)
        elements = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeCogElementDocument].self, forKey: .elements)
    }

    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elements, forKey: .elements)
    }
}

/// A cog's identity fields, uuid-free like every other `*Body`.
struct DopeCogBody: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int

    init(code: String, name: String, description: String, sortOrder: Int) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
    }
}

/// One top-level element (today: always a Hull) plus its collapsed links.
struct DopeCogElementDocument: Codable, Hashable, Sendable {
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let elementType: String
    let primaryPath: String?
    let dopeScopeCode: String?
    let links: DopeCogLinks?

    init(
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        elementType: String,
        primaryPath: String? = nil,
        dopeScopeCode: String? = nil,
        links: DopeCogLinks? = nil
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
struct DopeCogLinks: Codable, Hashable, Sendable {
    let persistenceOwners: [String]

    init(persistenceOwners: [String]) {
        self.persistenceOwners = persistenceOwners
    }
}
