import Foundation
import GmDaemonSdk

/// The pen's tool surface as a LIBRARY entry point — one call, one rendered
/// result — so the kernel can serve `MCP_CALL` without a second copy of the
/// roster, the narrowing table, or the budget logic.
///
/// WHY THIS EXISTS RATHER THAN A DISPATCH TABLE IN THE KERNEL. The obvious
/// shape for `MCP_CALL` was to map a tool name to a `MessageType` and forward
/// it. That works for the ~50 tools that are 1:1 with a verb and quietly loses
/// everything else the pen does: the composites that fan out to several verbs,
/// the per-tool `narrowing` that tells a caller WHAT to narrow, and the
/// `degrade` closures that re-run a narrowed call so an over-budget read gets
/// DATA plus instructions instead of a refusal. Those live in the `Tool` values
/// below and nowhere else. Reaching them through one function keeps the pen's
/// behaviour identical whether it is reached over stdio or over the wire.
///
/// THE STDIO PATH STILL USES THE SAME VALUES. `GmMcpServer.main()` has not
/// changed; both doors read the one `tools` array, so `tools/list` and
/// `MCP_CALL` cannot answer differently about what exists.
public enum GmPenTools {

    /// Every tool name this build serves. The runtime half of the bidirectional
    /// name-parity check — the build-time half stops a generated plugin naming
    /// a tool nothing serves, and this answers the reverse question for a
    /// caller that arrives with an unknown name.
    public static var names: Set<String> {
        Set(tools.map(\.name))
    }

    /// Run one tool and render its result under `PenResultBudget`.
    ///
    /// - Parameter caller: how this body reaches the daemon. `DaemonClient` on
    ///   the stdio path; `KernelVerbCaller` when the kernel serves `MCP_CALL`,
    ///   which is what puts the body inside the ambient transaction boundary and
    ///   gives a composite tool one transaction instead of N.
    /// - Returns: the rendered JSON, already budget-checked. Over-budget results
    ///   come back as the `gmcc_oversize` envelope rather than truncated JSON.
    /// - Throws: `GmPenToolError.unknownTool` for a name this build does not
    ///   serve; whatever the tool body throws otherwise.
    public static func call(
        tool name: String,
        arguments: GmJsonValue?,
        caller: any GmVerbCaller
    ) throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw GmPenToolError.unknownTool(name)
        }
        let args = Args(json: try Self.bridge(arguments))
        let value = try tool.run(args, caller)
        return try renderResult(tool: tool, args: args, client: caller, value: value)
    }

    /// `GmJsonValue` (the wire's untyped value) to the pen's own internal `JSON`.
    ///
    /// AN ENCODE/PARSE ROUND TRIP, NOT A HAND-WRITTEN CONVERTER, and the choice
    /// is deliberate. A case-by-case mapping between two JSON enums is the kind
    /// of code that looks obviously correct and silently disagrees on the edges
    /// — integers versus doubles being the one that bites here, since
    /// `GmJsonValue` distinguishes `.int`/`.double` while `JSON` carries a single
    /// `.number(Double)` and re-derives integrality on the way out. Serializing
    /// and re-parsing routes both through `JSONSerialization`, which is the same
    /// path the stdio door already takes, so the two doors cannot disagree about
    /// what an argument means.
    private static func bridge(_ value: GmJsonValue?) throws -> JSON {
        guard let value else { return .object([:]) }
        let data = try JSONEncoder().encode(value)
        return JSON.parse(data) ?? .object([:])
    }
}

public enum GmPenToolError: Error, CustomStringConvertible {
    case unknownTool(String)

    public var description: String {
        switch self {
        case .unknownTool(let name):
            return "'\(name)' is not a tool this build serves. "
                + "The pen roster is generated from VerbRegistry; `gm_hook verbs --json` lists every verb."
        }
    }
}

/// One served tool, as DATA — what the plugin generator writes into the harness
/// manifests.
///
/// The generator reads THIS rather than a hand-kept list, which is what makes
/// "the plugin names a tool the server does not serve" unrepresentable instead
/// of merely checked. `tools/list` and the generated `allowed-tools` frontmatter
/// are then two renderings of one array.
public struct GmPenToolDescriptor: Sendable, Hashable {
    public let name: String
    public let description: String
    /// The published JSON Schema, already in wire shape.
    ///
    /// Serialized to `Data` rather than handed over as a live object because
    /// the schema is built from `[String: Any]` on this side and the generator
    /// lives behind a macOS 27 floor with its own JSON type. Bytes cross that
    /// boundary without either side learning the other's representation.
    public let inputSchemaJSON: Data
    /// True when the verb behind this tool RECORDS. The generator uses it to
    /// decide which tools a read-only agent may be granted, and it is derived
    /// from `VerbRegistry.role` rather than from the tool name, so it cannot
    /// drift from what the daemon actually does.
    public let isWrite: Bool
}

extension GmPenTools {
    /// The served roster, in a form something outside this module can render.
    ///
    /// SORTED BY NAME so a regenerated plugin is diffable. An unordered roster
    /// makes every regeneration look like a change to every file, which is how
    /// a real change gets lost in the noise of a reordering.
    @MainActor public static var descriptors: [GmPenToolDescriptor] {
        let writes = VerbRegistry.writePenTools
        return tools
            .sorted { $0.name < $1.name }
            .map { tool in
                let schema = (try? JSONSerialization.data(
                    withJSONObject: tool.inputSchema, options: [.sortedKeys])) ?? Data("{}".utf8)
                return GmPenToolDescriptor(
                    name: tool.name,
                    description: tool.description,
                    inputSchemaJSON: schema,
                    isWrite: writes.contains(tool.name))
            }
    }
}
