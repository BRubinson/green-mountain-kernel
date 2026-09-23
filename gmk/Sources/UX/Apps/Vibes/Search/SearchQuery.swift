import Foundation

// Unified search value with two opposite semantics, so one raw string drives both the list
// filter and find-in-page without two predicates.
//
//   .tokenized — trimmed and split on whitespace; a haystack matches if it contains ANY token,
//                case and diacritic insensitive. A whitespace-only query yields no tokens and
//                therefore matches NOTHING. Drives the prompt-list and project-load filters.
//   .literal   — the trimmed whole string; `ranges(in:)` enumerates every occurrence. Drives
//                find-in-page, which needs exact substrings, one range per match.
struct SearchQuery: Equatable {
    enum Mode: Equatable { case tokenized, literal }

    let literal: String
    let tokens: [String]
    /// Tokens with the session-code slug applied (`/` → `__`) — matching runs
    /// in the LOSSLESS direction (slug the query, never unslug a code), so a
    /// user typing `feature/login` finds the session coded `feature__login`.
    ///
    /// Computed once here: per-row derivation would allocate on every match.
    let sluggedTokens: [String]
    let mode: Mode

    /// Creates a search query from a raw string.
    ///
    /// - Parameters:
    ///   - raw: The user-entered search string.
    ///   - mode: The matching mode; `.tokenized` by default.
    init(_ raw: String, mode: Mode = .tokenized) {
        self.literal = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokens = literal.split(whereSeparator: \.isWhitespace).map(String.init)
        self.sluggedTokens = tokens.map { $0.replacingOccurrences(of: "/", with: "__") }
        self.mode = mode
    }

    // True only when there is something to match on (non-blank).
    var isActive: Bool { !literal.isEmpty }

    /// True when the query matches any of the given fields (tokenized OR-match).
    ///
    /// Returns false when the query is inactive (blank).
    ///
    /// - Parameter fields: The fields to test against.
    /// - Returns: True if any token matches any field; `false` if query is inactive.
    func matchesAny(_ fields: String...) -> Bool { matchesAny(fields) }

    /// True when the query matches any of the given fields (tokenized OR-match).
    ///
    /// Returns false when the query is inactive (blank).
    ///
    /// - Parameter fields: The fields to test against.
    /// - Returns: True if any token matches any field; `false` if query is inactive.
    func matchesAny(_ fields: [String]) -> Bool {
        guard isActive else { return false }
        return tokens.contains { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    /// True when the query matches any of the given session codes (slugged OR-match).
    ///
    /// Matches using slugged tokens to handle session codes correctly.
    ///
    /// - Parameter fields: The session code fields to test against.
    /// - Returns: True if any slugged token matches any field; `false` if query is inactive.
    func matchesAnySlugged(_ fields: String...) -> Bool {
        guard isActive else { return false }
        return sluggedTokens.contains { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    /// Every range of the literal query within text, left to right and non-overlapping.
    ///
    /// - Parameter text: The text to search within.
    /// - Returns: An array of ranges where the query occurs in the text.
    func ranges(in text: String) -> [Range<String.Index>] {
        guard isActive, !text.isEmpty else { return [] }
        var out: [Range<String.Index>] = []
        var lower = text.startIndex
        while let found = text.range(
            of: literal,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: lower..<text.endIndex
        ) {
            out.append(found)
            // Advance at least one scalar so a zero-width / repeated match terminates.
            lower = found.isEmpty ? text.index(after: found.lowerBound) : found.upperBound
            if lower >= text.endIndex { break }
        }
        return out
    }
}
