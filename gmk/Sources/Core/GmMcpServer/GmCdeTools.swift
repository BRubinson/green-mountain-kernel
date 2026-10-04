import Foundation

/// The pen's tool surface as a LIBRARY entry point — one call, one rendered
/// result — so the kernel serves `MCP_CALL` without a second copy of the
/// roster, the narrowing table or the budget logic.
///
/// A dispatch table mapping a tool name to a `MessageType` would work for the tools that are 1:1 with a verb and lose
/// the rest: the composites that fan out to several verbs, the per-tool `narrowing`, and the `degrade` closures that
/// re-run a narrowed call so an over-budget read returns DATA plus instructions. Both doors read the one `tools` array,
/// so they cannot disagree about what exists.
enum GmCdeTools {

    /// Every tool name the roster declares.
    ///
    /// The runtime half of the bidirectional name-parity check — the build-time half stops a generated plugin naming a
    /// tool nothing serves, and this answers the reverse question for a caller that arrives with an unknown name.
    static var names: Set<String> {
        CdeToolRoster.names
    }

    /// Runs one tool and renders its result under budget.
    ///
    /// `caller` is `DaemonClient` on the stdio path and `KernelVerbCaller` when
    /// the kernel serves `MCP_CALL`, which is what puts the body inside the
    /// ambient transaction boundary and gives a composite tool one transaction
    /// instead of N.
    ///
    /// - Parameters:
    ///   - name: The tool name to invoke.
    ///   - arguments: The tool arguments as a wire JSON value, or nil.
    ///   - caller: The verb caller to execute the tool body.
    /// - Returns: The rendered JSON, already budget-checked. Over-budget results
    ///   come back as the `gmcc_oversize` envelope rather than truncated JSON.
    /// - Throws: `GmCdeToolError.unknownTool` for a name this build does not
    ///   serve; whatever the tool body throws otherwise.
    static func call(
        tool name: String,
        arguments: GmJsonValue?,
        caller: any GmVerbCaller
    ) throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw GmCdeToolError.unknownTool(name)
        }
        let args = Args(json: try Self.bridge(arguments))
        let op = tool.resolvedOp(args)
        let value = try tool.run(args, caller)
        return try renderResult(tool: tool, value: value, op: op)
    }

    /// Converts wire JSON value to the pen's internal JSON representation.
    ///
    /// AN ENCODE/PARSE ROUND TRIP, NOT A HAND-WRITTEN CONVERTER. A case-by-case
    /// mapping between two JSON enums disagrees silently on the edges, integers
    /// versus doubles being the one that bites: `GmJsonValue` distinguishes
    /// `.int`/`.double` while `JSON` carries one `.number(Double)`. Re-parsing
    /// routes both through `JSONSerialization`, the same path the stdio door
    /// takes, so the two doors cannot disagree about what an argument means.
    ///
    /// - Parameter value: The wire JSON value to convert, or nil.
    /// - Returns: The converted internal JSON representation, or empty object.
    /// - Throws: An encoding or parsing error if conversion fails.
    private static func bridge(_ value: GmJsonValue?) throws -> JSON {
        guard let value else { return .object([:]) }
        let data = try JSONEncoder().encode(value)
        return JSON.parse(data) ?? .object([:])
    }
}

enum GmCdeToolError: Error, CustomStringConvertible {
    case unknownTool(String)

    var description: String {
        switch self {
        case .unknownTool(let name):
            return "'\(name)' is not a tool this build serves. "
                + "Call cde_init for the workflow entry point; each phase's `gmcc:cde_rpir_<phase>` skill "
                + "names the tool and op that phase calls."
        }
    }
}
