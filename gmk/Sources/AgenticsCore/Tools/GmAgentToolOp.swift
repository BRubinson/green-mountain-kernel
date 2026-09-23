// One op of a cde tool: the wire verbs behind it and what a caller must pass.

import Foundation

/// A single `op` value of a consolidated cde tool.
///
/// Each tool declares a nested `enum Op: String, CaseIterable` and a
/// `static let ops: [GmAgentToolOp]` with one row per case, so the op vocabulary
/// an agent can see and the verbs it reaches are declared in one place.
struct GmAgentToolOp: Sendable {

    let op: String

    /// The daemon verbs this op sends, in the order it sends them.
    ///
    /// A composite op names every verb it folds.
    let verbs: [MessageType]

    /// The selectors a caller narrows with when the result is over budget.
    let narrowing: CdeNarrowing?

    /// Argument names this op refuses without.
    ///
    /// Required-ness is per OP, so the served schema cannot express it and the tool body checks it.
    let requiredParams: [String]

    let summary: String

    /// Creates an op descriptor with explicit parameters.
    ///
    /// - Parameters:
    ///   - op: The op name.
    ///   - verbs: The daemon verbs this op sends.
    ///   - summary: A one-line description of the op.
    ///   - narrowing: Optional selectors for over-budget results.
    ///   - requiredParams: Argument names the op requires.
    init(
        op: String,
        verbs: [MessageType],
        summary: String,
        narrowing: CdeNarrowing? = nil,
        requiredParams: [String] = []
    ) {
        self.op = op
        self.verbs = verbs
        self.narrowing = narrowing
        self.requiredParams = requiredParams
        self.summary = summary
    }

    /// Creates an op descriptor using an enum case for the name.
    ///
    /// Takes the op name from the tool's own `Op` case, so the enum the schema
    /// advertises and this table cannot spell the op differently.
    ///
    /// - Parameters:
    ///   - op: An enum case whose raw value is the op name.
    ///   - verbs: The daemon verbs this op sends.
    ///   - summary: A one-line description of the op.
    ///   - narrowing: Optional selectors for over-budget results.
    ///   - requiredParams: Argument names the op requires.
    init(
        _ op: some RawRepresentable<String>,
        verbs: [MessageType],
        summary: String,
        narrowing: CdeNarrowing? = nil,
        requiredParams: [String] = []
    ) {
        self.init(
            op: op.rawValue,
            verbs: verbs,
            summary: summary,
            narrowing: narrowing,
            requiredParams: requiredParams
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
