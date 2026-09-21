// One op of a cde tool: the wire verbs behind it and what a caller must pass.

import Foundation

/// A single `op` value of a consolidated cde tool.
///
/// Each tool declares a nested `enum Op: String, CaseIterable` and a
/// `static let ops: [GmAgentToolOp]` with one row per case, so the op vocabulary
/// an agent can see and the verbs it reaches are declared in one place.
struct GmAgentToolOp: Sendable {

    let op: String

    /// The daemon verbs this op sends, in the order it sends them. A composite
    /// op names every verb it folds.
    let verbs: [MessageType]

    /// The selectors a caller narrows with when the result is over budget.
    let narrowing: CdeNarrowing?

    /// Argument names this op refuses without. Required-ness is per OP, so the
    /// served schema cannot express it and the tool body checks it.
    let requiredParams: [String]

    let summary: String

    init(
        op: String,
        verbs: [MessageType],
        narrowing: CdeNarrowing? = nil,
        requiredParams: [String] = [],
        summary: String
    ) {
        self.op = op
        self.verbs = verbs
        self.narrowing = narrowing
        self.requiredParams = requiredParams
        self.summary = summary
    }

    /// Takes the op name from the tool's own `Op` case, so the enum the schema
    /// advertises and this table cannot spell the op differently.
    init(
        _ op: some RawRepresentable<String>,
        verbs: [MessageType],
        narrowing: CdeNarrowing? = nil,
        requiredParams: [String] = [],
        summary: String
    ) {
        self.init(
            op: op.rawValue,
            verbs: verbs,
            narrowing: narrowing,
            requiredParams: requiredParams,
            summary: summary
        )
    }

    /// True when any verb behind the op RECORDS, which is the one case where
    /// "call it again, narrower" is advice a caller must not follow.
    var isWrite: Bool {
        verbs.contains { verb in
            guard case .record = VerbRegistry.spec(for: verb)?.role else { return false }
            return true
        }
    }
}
