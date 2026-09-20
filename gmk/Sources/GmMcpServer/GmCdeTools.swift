import Foundation

/// The pen's tool surface as a LIBRARY entry point — one call, one rendered
/// result — so the kernel serves `MCP_CALL` without a second copy of the
/// roster, the narrowing table or the budget logic. A dispatch table mapping a
/// tool name to a `MessageType` would work for the tools that are 1:1 with a
/// verb and lose the rest: the composites that fan out to several verbs, the
/// per-tool `narrowing`, and the `degrade` closures that re-run a narrowed call
/// so an over-budget read returns DATA plus instructions. Both doors read the
/// one `tools` array, so they cannot disagree about what exists.
enum GmCdeTools {

    /// Every tool name this build serves. The runtime half of the bidirectional
    /// name-parity check — the build-time half stops a generated plugin naming
    /// a tool nothing serves, and this answers the reverse question for a
    /// caller that arrives with an unknown name.
    static var names: Set<String> {
        Set(tools.map(\.name))
    }

    /// Run one tool and render its result under `CdeResultBudget`.
    ///
    /// `caller` is `DaemonClient` on the stdio path and `KernelVerbCaller` when
    /// the kernel serves `MCP_CALL`, which is what puts the body inside the
    /// ambient transaction boundary and gives a composite tool one transaction
    /// instead of N.
    ///
    /// - Returns: the rendered JSON, already budget-checked. Over-budget results
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
        let value = try tool.run(args, caller)
        return try renderResult(tool: tool, value: value)
    }

    /// `GmJsonValue` (the wire's untyped value) to the pen's own internal `JSON`.
    ///
    /// AN ENCODE/PARSE ROUND TRIP, NOT A HAND-WRITTEN CONVERTER. A case-by-case
    /// mapping between two JSON enums disagrees silently on the edges, integers
    /// versus doubles being the one that bites: `GmJsonValue` distinguishes
    /// `.int`/`.double` while `JSON` carries one `.number(Double)`. Re-parsing
    /// routes both through `JSONSerialization`, the same path the stdio door
    /// takes, so the two doors cannot disagree about what an argument means.
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
struct GmCdeToolDescriptor: Sendable, Hashable {
    let name: String
    let description: String
    /// The published JSON Schema, already in wire shape.
    ///
    /// Serialized to `Data` rather than handed over as a live object because
    /// the schema is built from `[String: Any]` on this side and the generator
    /// lives behind a macOS 27 floor with its own JSON type. Bytes cross that
    /// boundary without either side learning the other's representation.
    let inputSchemaJSON: Data
    /// True when the verb behind this tool RECORDS. The generator uses it to
    /// decide which tools a read-only agent may be granted, and it is derived
    /// from `VerbRegistry.role` rather than from the tool name, so it cannot
    /// drift from what the daemon actually does.
    let isWrite: Bool
}

extension GmCdeTools {
    /// The served roster, in a form something outside this module can render.
    ///
    /// SORTED BY NAME so a regenerated plugin is diffable. An unordered roster
    /// makes every regeneration look like a change to every file, which is how
    /// a real change gets lost in the noise of a reordering.
    @MainActor static var descriptors: [GmCdeToolDescriptor] {
        let writes = VerbRegistry.writeCdeTools
        return
            tools
            .sorted { $0.name < $1.name }
            .map { tool in
                let schema =
                    (try? JSONSerialization.data(
                        withJSONObject: tool.inputSchema,
                        options: [.sortedKeys]
                    )) ?? Data("{}".utf8)
                return GmCdeToolDescriptor(
                    name: tool.name,
                    description: tool.description,
                    inputSchemaJSON: schema,
                    isWrite: writes.contains(tool.name)
                )
            }
    }
}
