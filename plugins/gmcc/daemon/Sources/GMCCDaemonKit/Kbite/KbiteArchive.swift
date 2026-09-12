import Foundation

// KBITE_EXPORT / KBITE_IMPORT archive codec — the durable db_export.json
// contract inside a gmcc_kbite_{code}_{date}.zip, plus the bidirectional
// path scrub. No schema of its own: the document mirrors the frozen m0001
// row families, keywords travel as TEXT (the shared vocabulary remaps via
// ensureKeyword on import), and no rowids or keyword uuids are ever written.

/// One prefix→placeholder substitution. Scrub direction replaces `prefix`
/// with `placeholder`; rehydrate replaces `placeholder` with `prefix`.
/// Rules are applied longest-prefix-first so `{root}/{code}` wins over a
/// bare `$HOME` that contains it.
public struct KbitePrefixRule: Codable, Hashable, Sendable {
    public let prefix: String
    public let placeholder: String

    public init(prefix: String, placeholder: String) {
        self.prefix = prefix
        self.placeholder = placeholder
    }
}

public enum KbiteArchive {
    /// db_export.json format version — gate imports on this, not on the
    /// plugin or wire version.
    public static let formatVersion = 1

    // Deliberately NOT of the retired GMCC_KBITE* env family —
    // DocsContractTests bans that spelling everywhere in docs.
    public static let treePlaceholder = "{{KBITE_TREE}}"
    public static let identityPlaceholder = "{{KBITE_IDENTITY}}"
    public static let ckfsPlaceholder = "{{GMCC_CKFS}}"
    public static let homePlaceholder = "{{GMCC_HOME}}"

    /// Archive codes come from UNTRUSTED zips and become filesystem path
    /// components on import — same snake_case shape every locally-typed code
    /// already has. One segment, no separators, no dots.
    public static func isValidCode(_ code: String) -> Bool {
        !code.isEmpty && code.count <= 100 && code.allSatisfy {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_"
        }
    }

    /// Machine roots → placeholders. Longest prefix first, so overlapping
    /// rules (a kbite root under $HOME) cannot half-replace each other.
    public static func scrub(_ text: String, rules: [KbitePrefixRule]) -> String {
        var out = text
        for rule in rules.sorted(by: { $0.prefix.count > $1.prefix.count }) where !rule.prefix.isEmpty {
            out = out.replacingOccurrences(of: rule.prefix, with: rule.placeholder)
        }
        return out
    }

    /// Placeholders → this machine's roots. Longest placeholder first for
    /// symmetry (placeholders never nest today, but the order costs nothing).
    public static func rehydrate(_ text: String, rules: [KbitePrefixRule]) -> String {
        var out = text
        for rule in rules.sorted(by: { $0.placeholder.count > $1.placeholder.count })
        where !rule.placeholder.isEmpty {
            out = out.replacingOccurrences(of: rule.placeholder, with: rule.prefix)
        }
        return out
    }

    public static func encode(_ document: KbiteExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> KbiteExportDocument {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(KbiteExportDocument.self, from: data)
    }
}

/// The whole portable kbite: one kbite row, its resources and files, and
/// every keyword attachment by text. `sourceKbiteUuid` is provenance only —
/// import always works by code and re-mints resource/file uuids (every
/// referrer is ghost-tolerant by design).
public struct KbiteExportDocument: Codable, Hashable, Sendable {
    public let formatVersion: Int
    public let code: String
    public let exportedAt: String
    public let sourceKbiteUuid: String
    public let kbiteKeywords: [String]
    public let resources: [Resource]

    public struct Resource: Codable, Hashable, Sendable {
        public let resourceName: String
        public let resourceSummary: String
        public let resourceType: String
        public let resourceTrust: Int
        public let files: [File]

        public init(
            resourceName: String,
            resourceSummary: String,
            resourceType: String,
            resourceTrust: Int,
            files: [File]
        ) {
            self.resourceName = resourceName
            self.resourceSummary = resourceSummary
            self.resourceType = resourceType
            self.resourceTrust = resourceTrust
            self.files = files
        }
    }

    /// A NULL content column round-trips as JSON null — the raw bytes live
    /// in the zip's digested/ tree (or nowhere, for binaries/oversized).
    public struct File: Codable, Hashable, Sendable {
        public let resourceFileName: String
        public let resourceFileSummary: String
        public let resourceFileContent: String?
        public let keywords: [String]

        public init(
            resourceFileName: String,
            resourceFileSummary: String,
            resourceFileContent: String?,
            keywords: [String]
        ) {
            self.resourceFileName = resourceFileName
            self.resourceFileSummary = resourceFileSummary
            self.resourceFileContent = resourceFileContent
            self.keywords = keywords
        }
    }

    public init(
        formatVersion: Int = KbiteArchive.formatVersion,
        code: String,
        exportedAt: String,
        sourceKbiteUuid: String,
        kbiteKeywords: [String],
        resources: [Resource]
    ) {
        self.formatVersion = formatVersion
        self.code = code
        self.exportedAt = exportedAt
        self.sourceKbiteUuid = sourceKbiteUuid
        self.kbiteKeywords = kbiteKeywords
        self.resources = resources
    }
}
