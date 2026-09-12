import Foundation

/// The agent-facing sheet, GENERATED FROM `VerbRegistry` rather than written
/// down.
///
/// Generation is the whole point: a hand-written sheet is prose ABOUT a
/// surface, so it can disagree with the surface. Reading the roster off the
/// registry the pen serves from makes that disagreement unrepresentable — a
/// tool cannot be listed here unless it exists, and cannot exist without being
/// listed.
///
/// TWO PROPERTIES, TWO BUDGETS. `instructions` is what the MCP server returns
/// from `initialize`, where the budget is tight (2048 bytes, asserted at
/// startup). `text` is what a spawning agent receives as SubagentStart context,
/// where there is room for the invariants an agent actually needs and cannot
/// infer from a tool schema.
public enum PenSheet {

    /// Compact orientation for the MCP `initialize` response.
    public static var instructions: String {
        let roster = self.roster
        return """
            The GMCC pen: the GM-CDE workflow machine's record, as tools.

            START HERE — bot_next returns your current phase, its instructions, \
            your uuid bundle, and the gate blockers. Call it before anything else, \
            and again after every seal. It answers without being told a uuid.

            THE RULE — where a pen tool exists, it is the write path. It is typed, \
            it threads expected_version, and it is what the record is made of.

            READ: \(roster.reads.joined(separator: ", ")).
            WRITE: \(roster.writes.joined(separator: ", ")).

            THE PRIMARY'S CALLS — \(roster.primaryCalls.joined(separator: ", ")). \
            Cross-agent calibration, the choice among options, and the seals \
            belong to one reader; unless your own tool list says otherwise, \
            report that you are ready for one rather than making it.
            """
    }

    /// The fuller sheet handed to a spawned agent at SubagentStart.
    ///
    /// THE INVARIANTS BLOCK IS THE LOAD-BEARING HALF. A tool schema conveys a
    /// parameter list and nothing else — it cannot tell an agent that the db is
    /// append-only, that a VERSION_CONFLICT is re-read-and-retry rather than a
    /// failure, or that a dope ref is a dot-path code and never a uuid.
    public static var text: String {
        """
        \(instructions)

        INVARIANTS
          - Thread expected_version on every mutation. On VERSION_CONFLICT, \
        re-run the matching get, take .version, and retry — it is a normal \
        outcome of concurrent work, not an error to report.
          - The db is APPEND-ONLY history. Nothing is wiped, and a row you \
        wrote by mistake is corrected by writing again, never by deletion.
          - SUMMARY_ABSENT means the prompt exists but that summary was never \
        opened — open it. It is never a reason to fall back to a file.
          - Dope refs are dot-path CODES (domain.entity.property), never uuids.
          - Rate your OWN findings 0 (critical) to 999 (ignore); the read \
        threshold is 100. Ranking is a single cross-agent calibration pass over \
        every agent's findings at once, so it is one reader's job, not yours.
          - Seal only your own summary. That seal is yours; another agent's is not.

        A VERB WITH NO PEN TOOL is reached the same way every daemon verb is: \
        gmcc_hook call <MESSAGE_TYPE> --json '{...}' (--json-file for a body \
        bigger than an argv). Wire keys are snake_case and are sent verbatim; \
        `gmcc_hook verbs --json` lists every type. If a pen tool you DO have \
        covers the write, use the pen tool — it is typed and it threads the \
        version for you.
        """
    }

    // MARK: - Generation

    struct Roster {
        var reads: [String]
        var writes: [String]
        var primaryCalls: [String]
    }

    /// Orientation before record before write: an agent that calls bot_next
    /// first never needs the rest of this text.
    static var roster: Roster {
        let leadReads = ["bot_next", "bot_get", "bot_current_prompt"]
        var reads: [String] = leadReads
        var writes: [String] = []
        var primaryCalls: [String] = []
        for spec in VerbRegistry.all.sorted(by: { $0.messageType.rawValue < $1.messageType.rawValue }) {
            guard let tool = spec.penTool else { continue }
            // The primary's four are listed on their own line rather than
            // among the writes — METHODOLOGY, not a gate. Named rather than
            // withheld, so an agent can say it is ready for a specific one
            // instead of reporting "blocked" without saying on what.
            if VerbRegistry.primaryPenTools.contains(tool) {
                primaryCalls.append(tool)
                continue
            }
            switch spec.role {
            case .read:
                if !reads.contains(tool) { reads.append(tool) }
            case .record:
                if !reads.contains(tool) { writes.append(tool) }
            }
        }
        for tool in VerbRegistry.compositePenTools.keys.sorted() where !reads.contains(tool) {
            reads.append(tool)
        }
        return Roster(reads: reads, writes: writes, primaryCalls: primaryCalls.sorted())
    }
}
