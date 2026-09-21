// The GmAgentTool protocol family and the tool-family vocabulary every tool declares itself under.

import Foundation
import FoundationModels

enum GmAgentToolFamily: String, Sendable, CaseIterable {

    case dope

    case kbite

    case diagram

    case cde

    case rpir

    case projects

    case system

    case fs
}

/// The transport every native tool call runs its op on.
///
/// The default is `DaemonClient`, the SOCKET transport: the right answer for a
/// model running outside the kernel. A process that already holds the store —
/// the app — must assign its own in-process caller here, or every native tool
/// call dials the daemon it is itself hosting.
enum GmAgentToolTransport {
    nonisolated(unsafe) static var caller: any GmVerbCaller = DaemonClient(clientName: "gm_agent")
}

protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }

    /// The caller this tool's ops run on. Defaults to the injected transport;
    /// a conformance overrides it only to pin itself to one caller.
    static var caller: any GmVerbCaller { get }

    /// One row per case of the tool's nested `Op` enum.
    static var ops: [GmAgentToolOp] { get }

    /// Whether the harness pins this tool into every session rather than
    /// deferring it until a caller asks for the roster.
    static var alwaysLoad: Bool { get }

    /// Whether the tool exists to answer with a refusal. A refusal carries no
    /// ops and is served but never granted.
    static var refuses: Bool { get }
}

extension GmAgentTool {

    static var alwaysLoad: Bool { false }

    static var refuses: Bool { false }

    static var caller: any GmVerbCaller { GmAgentToolTransport.caller }
}

extension GmAgentTool where Arguments: Generable, Output == String {

    /// Runs the tool through the same served dispatch the pen uses, so a native
    /// model and an MCP caller reach one implementation of every op.
    func call(arguments: Arguments) throws -> String {
        try GmCdeTools.call(
            tool: name,
            arguments: Self.wireArguments(arguments),
            caller: Self.caller
        )
    }

    /// The generated arguments as the wire's untyped value. Property names are
    /// snake_case, so the encoded keys are already the argument names the
    /// served tool reads.
    private static func wireArguments(_ arguments: Arguments) throws -> GmJsonValue? {
        let json = arguments.generatedContent.jsonString
        guard let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(GmJsonValue.self, from: data)
    }
}

protocol GmAgentDopeTool: GmAgentTool {}

extension GmAgentDopeTool {
    var family: GmAgentToolFamily { .dope }
}

protocol GmAgentKbiteTool: GmAgentTool {}

extension GmAgentKbiteTool {
    var family: GmAgentToolFamily { .kbite }
}

protocol GmAgentDiagramTool: GmAgentTool {}

extension GmAgentDiagramTool {
    var family: GmAgentToolFamily { .diagram }
}

protocol GmAgentCdeTool: GmAgentTool {}

extension GmAgentCdeTool {
    var family: GmAgentToolFamily { .cde }
}

protocol GmAgentRpirTool: GmAgentTool {}

extension GmAgentRpirTool {
    var family: GmAgentToolFamily { .rpir }
}

protocol GmAgentProjectsTool: GmAgentTool {}

extension GmAgentProjectsTool {
    var family: GmAgentToolFamily { .projects }
}

protocol GmAgentSystemTool: GmAgentTool {}

extension GmAgentSystemTool {
    var family: GmAgentToolFamily { .system }
}

protocol GmAgentFsTool: GmAgentTool {}

extension GmAgentFsTool {
    var family: GmAgentToolFamily { .fs }
}
