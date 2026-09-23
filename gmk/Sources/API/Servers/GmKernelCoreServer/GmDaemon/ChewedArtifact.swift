import Foundation

// Lenient section-scanner for {name}_chewed.md artifacts (the
// gmcc_agent_kbite_crunch_chew output contract). Deliberately dependency-free
// and tolerant, in the same spirit as GmFsYaml's yaml scanning: a malformed
// chewed file yields a thin ChewedArtifact (body always survives verbatim),
// never a parse error — digest must not lose a resource to format drift.

/// One row of the chewed file's Contents Overview table, back-filled with an
/// absolute path from the **Full Paths** list when a basename matches.
struct ChewedFileEntry: Hashable, Sendable {
    let name: String
    let type: String
    let description: String
    let fullPath: String?

    /// Creates a file entry from a chewed artifact table row.
    ///
    /// - Parameters:
    ///   - name: The file name.
    ///   - type: The file type or extension.
    ///   - description: A description of the file.
    ///   - fullPath: The full path to the file, if available.
    init(name: String, type: String, description: String, fullPath: String?) {
        self.name = name
        self.type = type
        self.description = description
        self.fullPath = fullPath
    }
}

struct ChewedArtifact: Hashable, Sendable {
    let resourceName: String
    let confidence: Int?
    /// The ENTIRE chewed markdown, verbatim → kbite_resource.resource_summary.
    let body: String
    let files: [ChewedFileEntry]
    let keywords: [String]

    /// Creates a chewed artifact from parsed components.
    ///
    /// - Parameters:
    ///   - resourceName: The name of the resource.
    ///   - confidence: A confidence score if available.
    ///   - body: The complete markdown body.
    ///   - files: The parsed file entries.
    ///   - keywords: The extracted keywords.
    init(resourceName: String, confidence: Int?, body: String, files: [ChewedFileEntry], keywords: [String]) {
        self.resourceName = resourceName
        self.confidence = confidence
        self.body = body
        self.files = files
        self.keywords = keywords
    }
}

enum ChewedArtifactParser {
    private enum Section {
        case header
        case contents
        case keywords
        case other
    }

    /// Parses a chewed markdown artifact.
    ///
    /// - Parameters:
    ///   - text: The markdown text to parse.
    ///   - fallbackName: The name to use if none is found in the text.
    /// - Returns: The parsed ChewedArtifact.
    static func parse(text: String, fallbackName: String) -> ChewedArtifact {
        var resourceName = fallbackName
        var confidence: Int?
        var entries: [ChewedFileEntry] = []
        var fullPaths: [String] = []
        var keywords: [String] = []
        var section = Section.header
        var inFullPaths = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section tracking keys off heading keywords, not the 1./4.
            // numbering, so renumbered templates keep parsing.
            if trimmed.hasPrefix("## ") {
                if trimmed.contains("Contents Overview") {
                    section = .contents
                } else if trimmed.contains("Keywords") {
                    section = .keywords
                } else {
                    section = .other
                }
                inFullPaths = false
                continue
            }

            switch section {
            case .header:
                if trimmed.hasPrefix("# Chewed:") {
                    let name = trimmed.dropFirst("# Chewed:".count).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { resourceName = name }
                } else if trimmed.hasPrefix("**Confidence**:") {
                    let value = trimmed.dropFirst("**Confidence**:".count).trimmingCharacters(in: .whitespaces)
                    confidence = Int(value.prefix(while: \.isNumber))
                }

            case .contents:
                if trimmed.hasPrefix("**Full Paths**") {
                    inFullPaths = true
                } else if inFullPaths, trimmed.hasPrefix("- ") {
                    let raw = trimmed.dropFirst(2)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                    if raw.hasPrefix("/") { fullPaths.append(raw) }
                } else if let cells = tableRowCells(trimmed), cells.count >= 3 {
                    let isHeader = cells[0].lowercased() == "file"
                    let isSeparator = cells.allSatisfy { cell in
                        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
                    }
                    if !isHeader && !isSeparator {
                        entries.append(
                            ChewedFileEntry(
                                name: cells[0],
                                type: cells[1],
                                description: cells[2],
                                fullPath: nil
                            )
                        )
                    }
                }

            case .keywords:
                // First non-empty, non-heading line is the comma-separated list;
                // later keyword tiers accumulate the same way.
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    for raw in trimmed.split(separator: ",") {
                        let keyword = normalizeKeyword(String(raw))
                        if !keyword.isEmpty && !keywords.contains(keyword) {
                            keywords.append(keyword)
                        }
                    }
                }

            case .other:
                break
            }
        }

        // Back-fill entry paths by basename match; unmatched paths become
        // standalone entries so raw files omitted from the table still digest.
        var files: [ChewedFileEntry] = entries
        for path in fullPaths {
            let basename = URL(fileURLWithPath: path).lastPathComponent
            if let index = files.firstIndex(where: { $0.fullPath == nil && $0.name == basename }) {
                let entry = files[index]
                files[index] = ChewedFileEntry(
                    name: entry.name,
                    type: entry.type,
                    description: entry.description,
                    fullPath: path
                )
            } else if !files.contains(where: { $0.fullPath == path }) {
                let ext = URL(fileURLWithPath: path).pathExtension
                files.append(ChewedFileEntry(name: basename, type: ext, description: "", fullPath: path))
            }
        }

        return ChewedArtifact(
            resourceName: resourceName,
            confidence: confidence,
            body: text,
            files: files,
            keywords: keywords
        )
    }

    /// Cells are trimmed of backticks as well as whitespace: chew agents
    /// routinely code-quote the File column, and a `` `path` `` cell resolves to
    /// nothing — the extension comes back as ``swift` `` and the synthesized path
    /// carries literal backticks, so the row digests empty and SILENTLY.
    ///
    /// Stripping here is what keeps the File column a real path.
    private static let cellTrim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "`"))

    /// Splits a markdown table row into trimmed cells.
    ///
    /// - Parameter trimmed: A line that may be a markdown table row.
    /// - Returns: An array of cell values, or nil if not a table row.
    private static func tableRowCells(_ trimmed: String) -> [String]? {
        guard trimmed.hasPrefix("|") else { return nil }
        let cells =
            trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: cellTrim) }
        return cells.isEmpty ? nil : cells
    }

    /// Normalizes a raw keyword to snake_case vocabulary format.
    ///
    /// Converts to lowercase, replaces spaces and hyphens with underscores,
    /// strips everything outside [a-z0-9_], and collapses runs of underscores.
    ///
    /// - Parameter raw: The keyword to normalize.
    /// - Returns: The normalized keyword.
    static func normalizeKeyword(_ raw: String) -> String {
        var result = ""
        var lastWasUnderscore = false
        for character in raw.lowercased().trimmingCharacters(in: .whitespaces) {
            let mapped: Character?
            if character.isLetter || character.isNumber {
                mapped = character
            } else if character == " " || character == "-" || character == "_" {
                mapped = "_"
            } else {
                mapped = nil
            }
            guard let mapped else { continue }
            if mapped == "_" {
                if lastWasUnderscore || result.isEmpty { continue }
                lastWasUnderscore = true
            } else {
                lastWasUnderscore = false
            }
            result.append(mapped)
        }
        while result.hasSuffix("_") { result.removeLast() }
        return result
    }

    /// Text types get their full content inlined into the db; everything else
    /// (images, archives, media, unknown binaries) stays filesystem-only.
    ///
    /// `m`/`mm` are here for the same reason `c`/`cc` are: they are the
    /// IMPLEMENTATION half of a language whose headers were already inlined.
    /// Omitting them made every Objective-C body digest as an empty row while
    /// its `.h` digested fine — a whole-language blind spot in the search index.
    private static let textExtensions: Set<String> = [
        "md", "markdown", "mdx", "txt", "rst",
        "swift", "py", "rb", "go", "rs", "c", "h", "cc", "cpp", "hpp", "java", "kt",
        "m", "mm", "hh", "cxx", "hxx",
        "ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "yaml", "yml",
        "vue", "svelte",
        "html", "htm", "css", "scss",
        "sh", "bash", "zsh", "fish", "tcsh", "ksh",
        "sql", "toml", "xml", "csv", "tsv",
        "proto", "plist", "entitlements", "sdef",
        "log", "conf", "ini", "env",
    ]

    /// Determines if a file's content is text-based and should be inlined.
    ///
    /// Text types are inlined into the database; other files remain
    /// filesystem-only.
    ///
    /// - Parameter fileName: The name of the file.
    /// - Returns: True if the file is a text type.
    static func isTextType(fileName: String) -> Bool {
        textExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }
}
