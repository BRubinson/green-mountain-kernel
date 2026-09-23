import Foundation

// KBITE_EXPORT / KBITE_IMPORT archive codec — the durable db_export.json
// contract inside a gmcc_kbite_{code}_{date}.zip, plus the bidirectional
// path scrub. No schema of its own: the document mirrors the frozen m0001
// row families, keywords travel as TEXT (the shared vocabulary remaps via
// ensureKeyword on import), and no rowids or keyword uuids are ever written.

/// One prefix→placeholder substitution.
///
/// Scrub direction replaces `prefix` with `placeholder`; rehydrate replaces
/// `placeholder` with `prefix`. Rules are applied longest-prefix-first so
/// `{root}/{code}` wins over a bare `$HOME` that contains it.
struct KbitePrefixRule: Codable, Hashable, Sendable {
    let prefix: String
    let placeholder: String

    /// Creates a prefix substitution rule.
    ///
    /// - Parameters:
    ///   - prefix: The path prefix to replace.
    ///   - placeholder: The placeholder text to use.
    init(prefix: String, placeholder: String) {
        self.prefix = prefix
        self.placeholder = placeholder
    }
}

enum KbiteArchive {
    /// db_export.json format version — gate imports on this, not on the
    /// plugin or wire version.
    static let formatVersion = 1

    // Deliberately NOT of the retired GMCC_KBITE* env family —
    // DocsContractTests bans that spelling everywhere in docs.
    static let treePlaceholder = "{{KBITE_TREE}}"
    static let identityPlaceholder = "{{KBITE_IDENTITY}}"
    static let gmfsPlaceholder = "{{GM_FS}}"
    static let homePlaceholder = "{{GMCC_HOME}}"

    /// True when the code is a valid archive identifier.
    ///
    /// Archive codes come from untrusted zips and become filesystem path
    /// components on import — same snake_case shape every locally-typed code
    /// already has. One segment, no separators, no dots.
    ///
    /// - Parameter code: The code to validate.
    /// - Returns: True if the code is valid.
    static func isValidCode(_ code: String) -> Bool {
        !code.isEmpty && code.count <= 100
            && code.allSatisfy {
                ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_"
            }
    }

    /// Replaces machine roots with placeholders.
    ///
    /// Longest prefix first, so overlapping rules (a kbite root under $HOME)
    /// cannot half-replace each other.
    ///
    /// - Parameters:
    ///   - text: The text to scrub.
    ///   - rules: The prefix-to-placeholder mappings to apply.
    /// - Returns: The scrubbed text.
    static func scrub(_ text: String, rules: [KbitePrefixRule]) -> String {
        var out = text
        for rule in rules.sorted(by: { $0.prefix.count > $1.prefix.count }) where !rule.prefix.isEmpty {
            out = out.replacingOccurrences(of: rule.prefix, with: rule.placeholder)
        }
        return out
    }

    /// Replaces placeholders with this machine's roots.
    ///
    /// Longest placeholder first for symmetry (placeholders never nest
    /// today, but the order costs nothing).
    ///
    /// - Parameters:
    ///   - text: The text to rehydrate.
    ///   - rules: The placeholder-to-prefix mappings to apply.
    /// - Returns: The rehydrated text.
    static func rehydrate(_ text: String, rules: [KbitePrefixRule]) -> String {
        var out = text
        for rule in rules.sorted(by: { $0.placeholder.count > $1.placeholder.count })
        where !rule.placeholder.isEmpty {
            out = out.replacingOccurrences(of: rule.placeholder, with: rule.prefix)
        }
        return out
    }

    /// Encodes a kbite export document to JSON.
    ///
    /// - Parameter document: The document to encode.
    /// - Returns: The JSON data.
    /// - Throws: `EncodingError` on serialization failure.
    static func encode(_ document: KbiteExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Decodes a kbite export document from JSON.
    ///
    /// - Parameter data: The JSON data to decode.
    /// - Returns: The decoded document.
    /// - Throws: `DecodingError` on deserialization failure.
    static func decode(_ data: Data) throws -> KbiteExportDocument {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(KbiteExportDocument.self, from: data)
    }
}

/// The whole portable kbite: one kbite row, its resources and files, and
/// every keyword attachment by text. `sourceKbiteUuid` is provenance only —
/// import always works by code and re-mints resource/file uuids (every
/// referrer is ghost-tolerant by design).
struct KbiteExportDocument: Codable, Hashable, Sendable {
    let formatVersion: Int
    let code: String
    let exportedAt: String
    let sourceKbiteUuid: String
    let kbiteKeywords: [String]
    let resources: [Resource]

    struct Resource: Codable, Hashable, Sendable {
        let resourceName: String
        let resourceSummary: String
        let resourceType: String
        let resourceTrust: Int
        let files: [File]

        /// Creates an export resource.
        ///
        /// - Parameters:
        ///   - resourceName: The resource name.
        ///   - resourceSummary: The resource description.
        ///   - resourceType: The resource type.
        ///   - resourceTrust: The trust level.
        ///   - files: The files in this resource.
        init(
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
    struct File: Codable, Hashable, Sendable {
        let resourceFileName: String
        let resourceFileSummary: String
        let resourceFileContent: String?
        let keywords: [String]

        /// Creates an export file.
        ///
        /// - Parameters:
        ///   - resourceFileName: The file name.
        ///   - resourceFileSummary: The file description.
        ///   - resourceFileContent: The file content, or nil if stored outside JSON.
        ///   - keywords: The keywords attached to this file.
        init(
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

    /// Creates a kbite export document.
    ///
    /// - Parameters:
    ///   - code: The archive code.
    ///   - exportedAt: The export timestamp.
    ///   - sourceKbiteUuid: The UUID of the kbite being exported.
    ///   - kbiteKeywords: The keywords for this kbite.
    ///   - resources: The resources in this kbite.
    ///   - formatVersion: The archive format version; defaults to current.
    init(
        code: String,
        exportedAt: String,
        sourceKbiteUuid: String,
        kbiteKeywords: [String],
        resources: [Resource],
        formatVersion: Int = KbiteArchive.formatVersion
    ) {
        self.formatVersion = formatVersion
        self.code = code
        self.exportedAt = exportedAt
        self.sourceKbiteUuid = sourceKbiteUuid
        self.kbiteKeywords = kbiteKeywords
        self.resources = resources
    }
}
