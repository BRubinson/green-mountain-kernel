import Foundation

/// The `.doped.json` document types — the SAME `*Body` structs as the wire
/// tree, minus `DopeNodeIdentity`. Uuid-freedom is by construction: these
/// types have nowhere to put one.
///
/// Layout on disk, directly under `{instance_root}/.gmcc/` (there is no
/// `dope/` level):
///
///     scope.doped.json                                     DopeScopeDocument
///     persistence/{code}/{code}.index.persistence.doped.json
///                                                DopePersistenceIndexDocument
///     persistence/{code}/{code}.entity.{entity}.persistence.doped.json
///                                                   DopeEntityFileDocument
///     persistence/{code}/{code}.enum.{enum}.persistence.doped.json
///                                                     DopeEnumFileDocument
///     cogs/{code}/{code}.index.cog.doped.json          (hulls; step 5)
///
/// One domain is a DIRECTORY of files, not one file. The assembled in-memory
/// form stays `DopePersistenceFileDocument`, so validation, ingest and the
/// overlay resolver never learn that the split happened — the fan-out lives
/// entirely in DopeRepoSandbox.
///
/// `version` appears in the scope file AND in every file beneath it and must
/// match everywhere — a mismatch means a hand-edit and read-repo reports it.
/// It IS `dope_scope.revision`.
///
/// scope_type is deliberately NOT persisted: only a SESSION_INSTANCE tree is
/// ever written to a repo (`Store.requireRepoWritableScope`), so storing it
/// would record a constant and invite a hand-edit to contradict the one tier
/// that is structurally possible.

public struct DopeScopeDocument: Codable, Hashable, Sendable {
    public let version: Int64
    public let scope: DopeScopeBody
    /// persistence_code → repo-relative index path. Read as DATA, never
    /// followed: the reader re-derives each value from its key and refuses a
    /// mismatched, absolute, or `..`-bearing entry.
    public let persistence: [String: String]
    /// cog_code → repo-relative cog index path. Same data-never-followed
    /// rule. Defaulted so a tree written before cogs existed still decodes.
    public let cogs: [String: String]

    private enum CodingKeys: String, CodingKey { case version, scope, persistence, cogs }

    public init(
        version: Int64, scope: DopeScopeBody,
        persistence: [String: String], cogs: [String: String] = [:]
    ) {
        self.version = version
        self.scope = scope
        self.persistence = persistence
        self.cogs = cogs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        scope = try c.decode(DopeScopeBody.self, forKey: .scope)
        persistence = try c.decode([String: String].self, forKey: .persistence)
        cogs = try c.decodeIfPresent([String: String].self, forKey: .cogs) ?? [:]
    }

    /// The domain's own directory, relative to `.gmcc/`.
    public static func expectedDirectory(forPersistenceCode code: String) -> String {
        "\(DopeDocumentCodec.persistenceDirectoryName)/\(code)"
    }

    public static func expectedFile(forPersistenceCode code: String) -> String {
        "\(expectedDirectory(forPersistenceCode: code))/\(code).index.persistence.doped.json"
    }

    public static func expectedCogDirectory(forCogCode code: String) -> String {
        "\(DopeDocumentCodec.cogsDirectoryName)/\(code)"
    }

    public static func expectedCogFile(forCogCode code: String) -> String {
        "\(expectedCogDirectory(forCogCode: code))/\(code).index.cog.doped.json"
    }
}

/// The per-domain index: the domain body itself, plus the same
/// map-is-data-never-followed contract one level deeper. The reader
/// re-derives every entity/enum file name from its KEY; a written path that
/// disagrees is refused rather than followed, which is what stops a
/// hand-edited index from redirecting a read — or a prune — outside its own
/// directory.
public struct DopePersistenceIndexDocument: Codable, Hashable, Sendable {
    public let version: Int64
    public let body: DopePersistenceBody
    /// entity_code → file name (basename, within this domain's directory).
    public let entities: [String: String]
    /// enum_code → file name.
    public let enums: [String: String]

    private enum CodingKeys: String, CodingKey { case version, entities, enums }

    public init(
        version: Int64, body: DopePersistenceBody,
        entities: [String: String], enums: [String: String]
    ) {
        self.version = version
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    public init(from decoder: Decoder) throws {
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        entities = try c.decode([String: String].self, forKey: .entities)
        enums = try c.decode([String: String].self, forKey: .enums)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(entities, forKey: .entities)
        try c.encode(enums, forKey: .enums)
    }

    /// File names are keyed by CODE, never display name: codes are what
    /// dot-path refs resolve against, they survive a rename of the display
    /// name, and they cannot collide on a case-insensitive filesystem the
    /// way two differently-cased names would.
    public static func expectedEntityFile(domain: String, entity: String) -> String {
        "\(domain).entity.\(entity)\(DopeDocumentCodec.persistenceFileSuffix)"
    }

    public static func expectedEnumFile(domain: String, enumCode: String) -> String {
        "\(domain).enum.\(enumCode)\(DopeDocumentCodec.persistenceFileSuffix)"
    }
}

public struct DopeOptionDocument: Codable, Hashable, Sendable {
    public let body: DopeOptionBody

    public init(body: DopeOptionBody) { self.body = body }
    public init(from decoder: Decoder) throws { body = try DopeOptionBody(from: decoder) }
    public func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
}

public struct DopeEnumDocument: Codable, Hashable, Sendable {
    public let body: DopeEnumBody
    public let options: [DopeOptionDocument]

    private enum CodingKeys: String, CodingKey { case options }

    public init(body: DopeEnumBody, options: [DopeOptionDocument]) {
        self.body = body
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        body = try DopeEnumBody(from: decoder)
        options = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopeOptionDocument].self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(options, forKey: .options)
    }
}

public struct DopePropertyDocument: Codable, Hashable, Sendable {
    public let body: DopePropertyBody

    public init(body: DopePropertyBody) { self.body = body }
    public init(from decoder: Decoder) throws { body = try DopePropertyBody(from: decoder) }
    public func encode(to encoder: Encoder) throws { try body.encode(to: encoder) }
}

public struct DopeEntityDocument: Codable, Hashable, Sendable {
    public let body: DopeEntityBody
    public let properties: [DopePropertyDocument]

    private enum CodingKeys: String, CodingKey { case properties }

    public init(body: DopeEntityBody, properties: [DopePropertyDocument]) {
        self.body = body
        self.properties = properties
    }

    public init(from decoder: Decoder) throws {
        body = try DopeEntityBody(from: decoder)
        properties = try decoder.container(keyedBy: CodingKeys.self)
            .decode([DopePropertyDocument].self, forKey: .properties)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(properties, forKey: .properties)
    }
}

/// One `{domain}.entity.{code}.persistence.doped.json` file: a single entity
/// with its properties, plus the tree-wide version stamp.
public struct DopeEntityFileDocument: Codable, Hashable, Sendable {
    public let version: Int64
    public let body: DopeEntityBody
    public let properties: [DopePropertyDocument]

    private enum CodingKeys: String, CodingKey { case version, properties }

    public init(version: Int64, body: DopeEntityBody, properties: [DopePropertyDocument]) {
        self.version = version
        self.body = body
        self.properties = properties
    }

    public init(from decoder: Decoder) throws {
        body = try DopeEntityBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        properties = try c.decode([DopePropertyDocument].self, forKey: .properties)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(properties, forKey: .properties)
    }
}

/// One `{domain}.enum.{code}.persistence.doped.json` file.
public struct DopeEnumFileDocument: Codable, Hashable, Sendable {
    public let version: Int64
    public let body: DopeEnumBody
    public let options: [DopeOptionDocument]

    private enum CodingKeys: String, CodingKey { case version, options }

    public init(version: Int64, body: DopeEnumBody, options: [DopeOptionDocument]) {
        self.version = version
        self.body = body
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        body = try DopeEnumBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        options = try c.decode([DopeOptionDocument].self, forKey: .options)
    }

    public func encode(to encoder: Encoder) throws {
        try body.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(options, forKey: .options)
    }
}

/// The ASSEMBLED in-memory form of one domain — an index file plus its
/// entity and enum files, reassembled on read and fanned back out on write.
/// Deliberately unchanged in shape: DopeValidator, dopeIngest and the
/// overlay resolver all consume this and never learn that a domain is now a
/// directory rather than a file.
public struct DopePersistenceFileDocument: Codable, Hashable, Sendable {
    public let version: Int64
    public let body: DopePersistenceBody
    public let entities: [DopeEntityDocument]
    public let enums: [DopeEnumDocument]

    private enum CodingKeys: String, CodingKey { case version, entities, enums }

    public init(
        version: Int64, body: DopePersistenceBody,
        entities: [DopeEntityDocument], enums: [DopeEnumDocument]
    ) {
        self.version = version
        self.body = body
        self.entities = entities
        self.enums = enums
    }

    public init(from decoder: Decoder) throws {
        body = try DopePersistenceBody(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int64.self, forKey: .version)
        entities = try c.decode([DopeEntityDocument].self, forKey: .entities)
        enums = try c.decode([DopeEnumDocument].self, forKey: .enums)
    }

    public func encode(to encoder: Encoder) throws {
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
public struct DopeDocumentBundle: Codable, Hashable, Sendable {
    public let main: DopeScopeDocument
    public let domainFiles: [DopePersistenceFileDocument]
    /// The cogs area. Defaulted and decoded with decodeIfPresent so a tree
    /// written before cogs had a file layer still parses.
    public let cogFiles: [DopeCogDocument]

    private enum CodingKeys: String, CodingKey { case main, domainFiles, cogFiles }

    public init(
        main: DopeScopeDocument,
        domainFiles: [DopePersistenceFileDocument],
        cogFiles: [DopeCogDocument] = []
    ) {
        self.main = main
        self.domainFiles = domainFiles
        self.cogFiles = cogFiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        main = try c.decode(DopeScopeDocument.self, forKey: .main)
        domainFiles = try c.decode([DopePersistenceFileDocument].self, forKey: .domainFiles)
        cogFiles = try c.decodeIfPresent([DopeCogDocument].self, forKey: .cogFiles) ?? []
    }
}

/// The single coder pair for `.doped.json` files. Deliberately separate from
/// WireCodec — the file format and the socket format must be free to diverge.
/// `.sortedKeys` + `.prettyPrinted` make the writer byte-deterministic, so an
/// unchanged tree re-written by write-repo leaves `git status` clean.
public enum DopeDocumentCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// The scope index, directly under `.gmcc/`.
    public static let scopeFileName = "scope.doped.json"
    public static let persistenceDirectoryName = "persistence"
    public static let cogsDirectoryName = "cogs"
    /// Shared suffix of every per-entity/per-enum file.
    public static let persistenceFileSuffix = ".persistence.doped.json"
    public static let cogFileSuffix = ".cog.doped.json"
    /// The retired layout, kept ONLY so boot sync and the health check can
    /// recognise a stale tree and say so out loud instead of silently
    /// reporting "no dope here".
    public static let legacyDopeDirectoryName = "dope"
    public static let legacyMainFileName = "main.doped.json"
}
