import Foundation

/// Turns what a person actually types — `10`, `p10`, `fast_startup`, `startup` —
/// into a prompt uuid.
///
/// THE GAP THIS CLOSES: every prompt verb takes `--prompt-uuid` and nothing
/// else. Resolving the seq a user typed meant listing every prompt in the
/// session and filtering client-side, which is a round trip plus hand-written
/// glue at every call site, re-invented slightly differently each time.
///
/// PURE ON PURPOSE. It folds over the stubs `PROMPT_LIST` already returns, so it
/// needs no wire verb, no handler, and no migration — the `prompt` table already
/// declares `UNIQUE(session_uuid, seq)` and `UNIQUE(session_uuid, code)`, which
/// is what makes seq and code single-valued answers rather than best guesses.
///
/// AMBIGUITY IS A RESULT, NEVER A GUESS. A substring that matches three prompts
/// returns all three for the caller to disambiguate. Silently picking the first
/// would file a session's work against the wrong prompt, and the append-only db
/// means that mistake is permanent.
public enum PromptResolver {

    /// How a selector matched — surfaced so a caller can tell an exact hit from
    /// a fuzzy one and say so.
    public enum MatchKind: String, Sendable {
        case seq
        case code
        case name
        case nameSubstring
    }

    public enum Resolution: Sendable {
        case matched(stub: PromptStub, by: MatchKind)
        /// More than one candidate. Ordered by seq so the caller can present
        /// them the way the user thinks about them.
        case ambiguous([PromptStub])
        case notFound
    }

    /// Resolve `selector` against one session's prompts.
    ///
    /// Precedence is most-specific-first, and each tier is tried to exhaustion
    /// before the next: an exact name must never lose to a substring hit on a
    /// different prompt.
    public static func resolve(_ selector: String, in stubs: [PromptStub]) -> Resolution {
        let needle = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .notFound }

        // 1. A bare integer is a seq. UNIQUE(session_uuid, seq) makes this
        //    single-valued; more than one hit means the constraint is gone and
        //    the caller deserves to be told rather than handed a coin flip.
        if let seq = Int64(needle) {
            let hits = stubs.filter { $0.seq == seq }
            if hits.count == 1 { return .matched(stub: hits[0], by: .seq) }
            if hits.count > 1 { return .ambiguous(sortedBySeq(hits)) }
        }

        // 2. The code (`p10`), likewise UNIQUE per session.
        let lowered = needle.lowercased()
        let codeHits = stubs.filter { $0.code.lowercased() == lowered }
        if codeHits.count == 1 { return .matched(stub: codeHits[0], by: .code) }
        if codeHits.count > 1 { return .ambiguous(sortedBySeq(codeHits)) }

        // 3. An exact name, case-insensitively.
        let nameHits = stubs.filter { $0.name.lowercased() == lowered }
        if nameHits.count == 1 { return .matched(stub: nameHits[0], by: .name) }
        if nameHits.count > 1 { return .ambiguous(sortedBySeq(nameHits)) }

        // 4. A unique substring — the convenience tier, and the only one that
        //    can be ambiguous in normal use.
        let substringHits = stubs.filter { $0.name.lowercased().contains(lowered) }
        if substringHits.count == 1 { return .matched(stub: substringHits[0], by: .nameSubstring) }
        if substringHits.count > 1 { return .ambiguous(sortedBySeq(substringHits)) }

        return .notFound
    }

    private static func sortedBySeq(_ stubs: [PromptStub]) -> [PromptStub] {
        stubs.sorted { $0.seq < $1.seq }
    }
}
