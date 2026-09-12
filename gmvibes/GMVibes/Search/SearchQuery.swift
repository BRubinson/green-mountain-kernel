import Foundation

// Unified search value type with two opposite semantics, so the same raw string
// drives both the list filter and the in-view find-in-page without two predicates.
//
//   .tokenized  — trim, split on whitespace; a haystack matches if it contains
//                 (individually) ANY of the tokens (token-OR, case/diacritic
//                 insensitive). A whitespace-only query yields no tokens and
//                 therefore matches NOTHING (a deliberate fix vs the old
//                 whole-string `matches(query:)`, which matched ~everything on a
//                 lone space). Used by the prompt-list + project-load filters.
//   .literal    — the trimmed whole string; `ranges(in:)` enumerates every
//                 occurrence. Used by find-in-page (exact substring, per match).
struct SearchQuery: Equatable {
    enum Mode: Equatable { case tokenized, literal }

    let literal: String
    let tokens: [String]
    /// Tokens with the session-code slug applied (`/` → `__`) — matching runs
    /// in the LOSSLESS direction (slug the query, never unslug a code), so a
    /// user typing `feature/login` finds the session coded `feature__login`.
    /// Computed once here: per-row derivation would allocate on every match.
    let sluggedTokens: [String]
    let mode: Mode

    init(_ raw: String, mode: Mode = .tokenized) {
        self.literal = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokens = literal.split(whereSeparator: \.isWhitespace).map(String.init)
        self.sluggedTokens = tokens.map { $0.replacingOccurrences(of: "/", with: "__") }
        self.mode = mode
    }

    // True only when there is something to match on (non-blank).
    var isActive: Bool { !literal.isEmpty }

    // Tokenized OR-match across the supplied fields. Inactive query ⇒ false
    // (callers treat "no active query" as "show everything" themselves).
    func matchesAny(_ fields: String...) -> Bool { matchesAny(fields) }

    func matchesAny(_ fields: [String]) -> Bool {
        guard isActive else { return false }
        return tokens.contains { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    // Slugged-token OR-match for session codes (see `sluggedTokens`).
    func matchesAnySlugged(_ fields: String...) -> Bool {
        guard isActive else { return false }
        return sluggedTokens.contains { token in
            fields.contains { $0.localizedStandardContains(token) }
        }
    }

    // Every range of the literal query within `text`, left to right, non-overlapping.
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
