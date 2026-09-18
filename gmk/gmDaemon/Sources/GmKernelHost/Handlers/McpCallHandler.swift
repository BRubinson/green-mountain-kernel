import Foundation
import GmDaemon
import GmDaemonSdk
import GmMcpServer

/// `MCP_CALL` — one MCP `tools/call`, served by the kernel. The tool body runs
/// HERE, where `StoreBoundary` is ambient and re-entrant, so a composite's
/// writes enlist in ONE boundary and land or roll back together.
///
/// The harness-side child PROCESS stays, thinned: `ClientKey.resolve()` walks
/// process ancestry for a `claude` parent and a kernel is not one, so the child
/// supplies the identity triple. `GmCdeTools.call` runs the same `Tool` values
/// the stdio door runs, so both doors share roster, narrowing and degrade.
enum McpCallHandler {

    static func handle(
        line: Data,
        head: EnvelopeHead,
        store: Store,
        caller: any GmVerbCaller
    ) throws -> HandlerResult {
        let req = try decodePayload(McpCallRequest.self, from: line)

        // ONE BOUNDARY FOR THE WHOLE TOOL, composite or not, so the composite
        // and 1:1 paths cannot drift in their atomicity. The two families that
        // refuse to compose — `checkpointTruncate` and the four-phase repo
        // verbs — throw `StoreError.notComposable` from inside; that propagates
        // and rolls back, and must not be caught and swallowed here.
        var rendered = ""
        var toolFailed: String?
        do {
            try store.inTransaction {
                rendered = try GmCdeTools.call(
                    tool: req.tool,
                    arguments: req.arguments,
                    caller: caller
                )
            }
        } catch let error as GmCdeToolError {
            // An unknown tool is a CALLER mistake, not a kernel fault: the
            // runtime half of the name-parity check, catching a stale cached
            // plugin against a newer kernel.
            throw StoreError.badRequest(detail: String(describing: error))
        } catch {
            // A TOOL-LEVEL failure rides the RESULT envelope with `isError`,
            // matching what the stdio server already does: a tool that fails is
            // not a malformed request, and an MCP client is built to read the
            // difference. Transport and framing failures still throw above.
            toolFailed = String(describing: error)
        }

        let response: McpCallResponse
        if let toolFailed {
            response = McpCallResponse(text: toolFailed, isError: true)
        } else {
            response = McpCallResponse(text: rendered, isError: false)
        }
        let envelope = ResponseEnvelope<McpCallResponse>(
            type: .mcpCall,
            requestId: head.requestId,
            ok: true,
            payload: response
        )
        return HandlerResult(line: try NDJSON.encodeLine(envelope))
    }
}
