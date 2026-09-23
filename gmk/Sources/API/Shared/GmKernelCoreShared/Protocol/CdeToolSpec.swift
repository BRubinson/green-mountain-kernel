import Foundation

/// One served cde tool: the name agents call, the schema Claude Code is shown,
/// and the ops it answers.
///
/// Values of this type are reflected from the
/// `GmAgentTool` declarations by `gm_kernel bridge` and read back out of the
/// generated `CdeToolRoster`, so nothing downstream hand-lists a tool name.
struct CdeToolSpec: Codable, Sendable {

    /// The ONE spelling of the tool name, snake_case.
    let name: String
    let description: String
    /// Pinned into every session's tool listing rather than loaded on demand.
    let alwaysLoad: Bool
    /// A published refusal: served so the answer is discoverable, granted to
    /// nobody, and carrying no ops by construction.
    let refuses: Bool
    /// The normalised wire schema, served to the harness verbatim.
    let schema: GmJsonValue
    let ops: [CdeOpSpec]

    /// What a grant, a hook payload or an error message must name.
    var qualifiedName: String { Self.qualifiedName(name) }

    /// The harness's plugin namespacing, spelled once for the whole tree.
    ///
    /// - Parameter tool: The tool name.
    /// - Returns: The qualified name with the plugin prefix.
    static func qualifiedName(_ tool: String) -> String { "mcp__plugin_gmcc_cde__" + tool }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case alwaysLoad = "always_load"
        case refuses
        case schema
        case ops
    }
}

/// One op on a tool: which daemon verbs it reaches, and what a caller needs
/// before choosing it.
struct CdeOpSpec: Codable, Sendable {

    let op: String
    /// The verbs this op sends.
    ///
    /// Empty for an op the pen folds itself.
    let verbs: [MessageType]
    /// True when any of those verbs records.
    ///
    /// A write that came back over budget
    /// must not be retried, so the guard needs this per OP and not per tool.
    let isWrite: Bool
    /// What a read op can be told to make itself smaller.
    let narrowing: CdeNarrowing?
    let requiredParams: [String]
    let summary: String

    enum CodingKeys: String, CodingKey {
        case op
        case verbs
        case isWrite = "is_write"
        case narrowing
        case requiredParams = "required_params"
        case summary
    }
}

/// The roster as values. `CdeToolRoster.json` is GENERATED; this extension is
/// the only thing that reads it.
extension CdeToolRoster {

    /// Quoted back when the generated constant will not decode.
    static let generatedPath =
        "gmk/Sources/API/Shared/GmKernelCoreShared/Protocol/CdeToolRoster.generated.swift"

    /// Decoded once, as an OUTCOME rather than a trap.
    ///
    /// A roster that will not
    /// decode is a build artifact nothing can serve, but what to do about it is
    /// the reader's call: the pen refuses to start, while a hook that only
    /// needs the sheet degrades to naming no tools instead of killing a session.
    static let specsResult: Result<[CdeToolSpec], Error> = Result {
        try rosterDecoder.decode([CdeToolSpec].self, from: Data(json.utf8))
    }

    /// The roster for every reader that cannot refuse.
    static var specs: [CdeToolSpec] { (try? specsResult.get()) ?? [] }

    /// Non-nil exactly when the generated constant would not decode, so the one
    /// reader that refuses can quote the reason.
    static var rosterDecodeError: Error? {
        guard case .failure(let error) = specsResult else { return nil }
        return error
    }

    /// Fetch the tool spec by name.
    ///
    /// - Parameter name: The tool name.
    /// - Returns: The spec, or `nil` if not found.
    static func spec(named name: String) -> CdeToolSpec? {
        specs.first { $0.name == name }
    }

    static var names: Set<String> { Set(specs.map(\.name)) }

    /// The tools pinned into every session's listing.
    static var pinned: Set<String> { Set(specs.filter(\.alwaysLoad).map(\.name)) }

    /// No key strategy on either coder: the coding keys above are the file's
    /// keys, and a strategy on one side only would rewrite half of them.
    static var rosterDecoder: JSONDecoder { JSONDecoder() }

    static var rosterEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
