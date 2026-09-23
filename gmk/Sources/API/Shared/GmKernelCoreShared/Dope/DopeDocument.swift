import Foundation

/// The `.doped.json` document types — the SAME `*Body` structs as the wire
/// tree, minus `DopeNodeIdentity`. Uuid-freedom is by construction: these
/// types have nowhere to put one. They live directly under
/// `{instance_root}/.gmcc/`, with one domain as a DIRECTORY of files; the
/// assembled in-memory form stays `DopePersistenceFileDocument`, so the
/// fan-out lives entirely in DopeRepoSandbox. `version` IS
/// `dope_scope.revision` and must match in the scope file and every file
/// beneath it; a mismatch means a hand-edit and read-repo reports it.

/// scope_type is deliberately NOT persisted: only a SESSION_INSTANCE tree can
/// be written to a repo, so storing it would record a constant and invite a
/// file that contradicts it.

struct DopeScopeDocument: Codable, Hashable, Sendable {
    let version: Int64
    let scope: DopeScopeBody
    /// persistence_code → repo-relative index path.
    ///
    /// Read as DATA, never followed: the reader re-derives each value from its key and
    /// refuses a mismatched, absolute, or `..`-bearing entry.
    let persistence: [String: String]
    /// cog_code → repo-relative cog index path.
    ///
    /// Same data-never-followed rule. Defaulted so a tree written before cogs existed still decodes.
    let cogs: [String: String]

    private enum CodingKeys: String, CodingKey { case version, scope, persistence, cogs }

    /// Creates a DopeScopeDocument with the version, scope, and file mappings.
    ///
    /// - Parameters:
    ///   - version: The dope tree's revision number.
    ///   - scope: The scope body defining the session instance and other metadata.
    ///   - persistence: A mapping from persistence domain codes to file paths.
    ///   - cogs: A mapping from cog codes to cog file paths; empty if cogs are not present.
    init(
        version: Int64,
        scope: DopeScopeBody,
        persistence: [String: String],
        cogs: [String: String] = [:]
    ) {
        self.version = version
        self.scope = scope
        self.persistence = persistence
        self.cogs = cogs
    }

    /// Decodes a DopeScopeDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        scope = try c.decode(DopeScopeBody.self, forKey: .scope)
        persistence = try c.decode([String: String].self, forKey: .persistence)
        cogs = try c.decodeIfPresent([String: String].self, forKey: .cogs) ?? [:]
    }

    /// The domain's own directory, relative to `.gmcc/`.
    ///
    /// - Parameter code: The persistence domain code.
    /// - Returns: The relative directory path.
    static func expectedDirectory(forPersistenceCode code: String) -> String {
        "\(DopeDocumentCodec.persistenceDirectoryName)/\(code)"
    }

    /// The domain's index file path.
    ///
    /// - Parameter code: The persistence domain code.
    /// - Returns: The relative file path.
    static func expectedFile(forPersistenceCode code: String) -> String {
        "\(expectedDirectory(forPersistenceCode: code))/\(code).index.persistence.doped.json"
    }

    /// The cog's own directory, relative to `.gmcc/`.
    ///
    /// - Parameter code: The cog code.
    /// - Returns: The relative directory path.
    static func expectedCogDirectory(forCogCode code: String) -> String {
        "\(DopeDocumentCodec.cogsDirectoryName)/\(code)"
    }

    /// The cog's index file path.
    ///
    /// - Parameter code: The cog code.
    /// - Returns: The relative file path.
    static func expectedCogFile(forCogCode code: String) -> String {
        "\(expectedCogDirectory(forCogCode: code))/\(code).index.cog.doped.json"
    }
}

/// The per-domain index: the domain body itself, plus the same map-is-data-never-followed contract one level deeper.
///
/// The reader re-derives every entity/enum file name from its KEY; a written path that
/// disagrees is refused rather than followed, which is what stops a hand-edited index from
/// redirecting a read — or a prune — outside its own directory.
struct DopePersistenceIndexDocument: Codable, Hashable, Sendable {
    let version: Int64
    let body: DopePersistenceBody
    /// entity_code → file name (basename, within this domain's directory).
    let entities: [String: String]
    /// enum_code → file name.
    let enums: [String: String]

    private enum CodingKeys: String, CodingKey { case version, entities, enums }

    /// Creates a DopePersistenceIndexDocument with version, body, and file mappings.
    ///
    /// - Parameters:
    ///   - version: The dope tree's revision number.
    ///   - body: The persistence domain body.
    ///   - entities: A mapping from entity codes to file names.
    ///   - enums: A mapping from enum codes to file names.
    init(
        version: Int64,
        body: DopePersistenceBody,
        entities: [String: String],
        enums: [String: String]
    ) {
        self.version = version
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    /// Decodes a DopePersistenceIndexDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        entities = try c.decode([String: String].self, forKey: .entities)
        enums = try c.decode([String: String].self, forKey: .enums)
    }

    /// Encodes the DopePersistenceIndexDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(entities, forKey: .entities)
        try c.encode(enums, forKey: .enums)
    }

    /// The entity's file name within its domain's directory.
    ///
    /// File names are keyed by code, not display name, so they survive a rename.
    ///
    /// - Parameters:
    ///   - domain: The persistence domain code.
    ///   - entity: The entity code.
    /// - Returns: The file name (basename, not a path).
    static func expectedEntityFile(domain: String, entity: String) -> String {
        "\(domain).entity.\(entity)\(DopeDocumentCodec.persistenceFileSuffix)"
    }

    /// The enum's file name within its domain's directory.
    ///
    /// - Parameters:
    ///   - domain: The persistence domain code.
    ///   - enumCode: The enum code.
    /// - Returns: The file name (basename, not a path).
    static func expectedEnumFile(domain: String, enumCode: String) -> String {
        "\(domain).enum.\(enumCode)\(DopeDocumentCodec.persistenceFileSuffix)"
    }
}

struct DopeOptionDocument: Codable, Hashable, Sendable {
    let body: DopeOptionBody

    /// Creates a DopeOptionDocument with the option body.
    ///
    /// - Parameter body: The option body.
    init(body: DopeOptionBody) { self.body = body }
    /// Decodes a DopeOptionDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws { body = try DopeOptionBody(from: decoder) }
    /// Encodes the DopeOptionDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
}

struct DopeEnumDocument: Codable, Hashable, Sendable {
    let body: DopeEnumBody
    let options: [DopeOptionDocument]

    private enum CodingKeys: String, CodingKey { case options }

    /// Creates a DopeEnumDocument with the enum body and its options.
    ///
    /// - Parameters:
    ///   - body: The enum body.
    ///   - options: The array of options in the enum.
    init(body: DopeEnumBody, options: [DopeOptionDocument]) {
        self.body = body
        self.options = options
    }

    /// Decodes a DopeEnumDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopeEnumBody(from: decoder)
        options = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeOptionDocument].self, forKey: .options)
    }

    /// Encodes the DopeEnumDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(options, forKey: .options)
    }
}

struct DopePropertyDocument: Codable, Hashable, Sendable {
    let body: DopePropertyBody

    /// Creates a DopePropertyDocument with the property body.
    ///
    /// - Parameter body: The property body.
    init(body: DopePropertyBody) { self.body = body }
    /// Decodes a DopePropertyDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws { body = try DopePropertyBody(from: decoder) }
    /// Encodes the DopePropertyDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
}

struct DopeEntityDocument: Codable, Hashable, Sendable {
    let body: DopeEntityBody
    let properties: [DopePropertyDocument]

    private enum CodingKeys: String, CodingKey { case properties }

    /// Creates a DopeEntityDocument with the entity body and its properties.
    ///
    /// - Parameters:
    ///   - body: The entity body.
    ///   - properties: The array of properties in the entity.
    init(body: DopeEntityBody, properties: [DopePropertyDocument]) {
        self.body = body
        self.properties = properties
    }

    /// Decodes a DopeEntityDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopeEntityBody(from: decoder)
        properties = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopePropertyDocument].self, forKey: .properties)
    }

    /// Encodes the DopeEntityDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(properties, forKey: .properties)
    }
}

/// One `{domain}.entity.{code}.persistence.doped.json` file: a single entity
/// with its properties, plus the tree-wide version stamp.
struct DopeEntityFileDocument: Codable, Hashable, Sendable {
    let version: Int64
    let body: DopeEntityBody
    let properties: [DopePropertyDocument]

    private enum CodingKeys: String, CodingKey { case version, properties }

    /// Creates a DopeEntityFileDocument with version, entity body, and properties.
    ///
    /// - Parameters:
    ///   - version: The dope tree's revision number.
    ///   - body: The entity body.
    ///   - properties: The array of properties in the entity.
    init(version: Int64, body: DopeEntityBody, properties: [DopePropertyDocument]) {
        self.version = version
        self.body = body
        self.properties = properties
    }

    /// Decodes a DopeEntityFileDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopeEntityBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        properties = try c.decode([DopePropertyDocument].self, forKey: .properties)
    }

    /// Encodes the DopeEntityFileDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(properties, forKey: .properties)
    }
}

/// One `{domain}.enum.{code}.persistence.doped.json` file.
struct DopeEnumFileDocument: Codable, Hashable, Sendable {
    let version: Int64
    let body: DopeEnumBody
    let options: [DopeOptionDocument]

    private enum CodingKeys: String, CodingKey { case version, options }

    /// Creates a DopeEnumFileDocument with version, enum body, and options.
    ///
    /// - Parameters:
    ///   - version: The dope tree's revision number.
    ///   - body: The enum body.
    ///   - options: The array of options in the enum.
    init(version: Int64, body: DopeEnumBody, options: [DopeOptionDocument]) {
        self.version = version
        self.body = body
        self.options = options
    }

    /// Decodes a DopeEnumFileDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopeEnumBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        options = try c.decode([DopeOptionDocument].self, forKey: .options)
    }

    /// Encodes the DopeEnumFileDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(options, forKey: .options)
    }
}

/// The ASSEMBLED in-memory form of one domain — an index file plus its entity and enum
/// files, reassembled on read and fanned back out on write.
///
/// Deliberately unchanged in shape: DopeValidator, dopeIngest and the overlay resolver all
/// consume this and never learn that a domain is now a directory rather than a file.
struct DopePersistenceFileDocument: Codable, Hashable, Sendable {
    let version: Int64
    let body: DopePersistenceBody
    let entities: [DopeEntityDocument]
    let enums: [DopeEnumDocument]

    private enum CodingKeys: String, CodingKey { case version, entities, enums }

    /// Creates a DopePersistenceFileDocument with version, domain body, entities, and enums.
    ///
    /// - Parameters:
    ///   - version: The dope tree's revision number.
    ///   - body: The persistence domain body.
    ///   - entities: The array of entities in the domain.
    ///   - enums: The array of enums in the domain.
    init(
        version: Int64,
        body: DopePersistenceBody,
        entities: [DopeEntityDocument],
        enums: [DopeEnumDocument]
    ) {
        self.version = version
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    /// Decodes a DopePersistenceFileDocument from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        entities = try c.decode([DopeEntityDocument].self, forKey: .entities)
        enums = try c.decode([DopeEnumDocument].self, forKey: .enums)
    }

    /// Encodes the DopePersistenceFileDocument to JSON.
    ///
    /// - Parameter encoder: The JSON encoder.
    /// - Throws: `EncodingError` when encoding fails.
    func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(entities, forKey: .entities)
        try c.encode(enums, forKey: .enums)
    }
}

/// The complete parsed on-disk representation of one scope. `main` is the
/// scope index document (`scope.doped.json`); `domainFiles` are the assembled
/// domains, each gathered from its own directory.
struct DopeDocumentBundle: Codable, Hashable, Sendable {
    let main: DopeScopeDocument
    let domainFiles: [DopePersistenceFileDocument]
    /// The cogs area.
    ///
    /// Defaulted and decoded with decodeIfPresent so a tree written before cogs had a file
    /// layer still parses.
    let cogFiles: [DopeCogDocument]

    private enum CodingKeys: String, CodingKey { case main, domainFiles, cogFiles }

    /// Creates a DopeDocumentBundle with the scope document, domain files, and cog files.
    ///
    /// - Parameters:
    ///   - main: The scope index document.
    ///   - domainFiles: The array of persistence domain documents.
    ///   - cogFiles: The array of cog documents; empty if cogs are not present.
    init(
        main: DopeScopeDocument,
        domainFiles: [DopePersistenceFileDocument],
        cogFiles: [DopeCogDocument] = []
    ) {
        self.main = main
        self.domainFiles = domainFiles
        self.cogFiles = cogFiles
    }

    /// Decodes a DopeDocumentBundle from JSON.
    ///
    /// - Parameter decoder: The JSON decoder.
    /// - Throws: `DecodingError` when the JSON is malformed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        main = try c.decode(DopeScopeDocument.self, forKey: .main)
        domainFiles = try c.decode([DopePersistenceFileDocument].self, forKey: .domainFiles)
        cogFiles = try c.decodeIfPresent([DopeCogDocument].self, forKey: .cogFiles) ?? []
    }
}

/// The single coder pair for `.doped.json` files.
///
/// Deliberately separate from WireCodec — the file format and the socket format must be free
/// to diverge. `.sortedKeys` + `.prettyPrinted` make the writer byte-deterministic, so an
/// unchanged tree re-written by write-repo leaves `git status` clean.
enum DopeDocumentCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// The scope index, directly under `.gmcc/`.
    static let scopeFileName = "scope.doped.json"
    static let persistenceDirectoryName = "persistence"
    static let cogsDirectoryName = "cogs"
    /// Shared suffix of every per-entity/per-enum file.
    static let persistenceFileSuffix = ".persistence.doped.json"
    static let cogFileSuffix = ".cog.doped.json"
    /// The retired layout, kept ONLY so boot sync and the health check can
    /// recognise a stale tree and say so out loud instead of silently
    /// reporting "no dope here".
    static let legacyDopeDirectoryName = "dope"
    static let legacyMainFileName = "main.doped.json"
}
