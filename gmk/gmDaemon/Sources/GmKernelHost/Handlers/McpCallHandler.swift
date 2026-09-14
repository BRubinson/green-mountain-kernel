import Foundation
import GmDaemon
import GmDaemonSdk
import GmMcpServer

/// `MCP_CALL` — one MCP `tools/call`, served by the kernel.
///
/// WHAT THIS REPLACES. The pen server used to hold a `DaemonClient` and relay
/// every tool over the socket: harness → `gm_mcp` → socket → kernel. Each verb
/// inside a tool body was its own round trip and its own transaction, so a
/// composite that writes twelve rows wrote twelve commits and a failure at the
/// seventh left six behind. Now the body runs HERE, inside the kernel, where
/// `StoreBoundary` is ambient and re-entrant — so those writes enlist in ONE
/// boundary and land or roll back together.
///
/// WHAT IT DOES NOT REPLACE: the harness-side child PROCESS. It stays, thinned.
/// `ClientKey.resolve()` walks process ancestry for a `claude` parent and that
/// string is the activation-claim key; a kernel is not a claude descendant, so
/// it cannot derive one. The child sends the identity triple instead — see
/// `GmHarnessIdentity`, which carries the full reasoning.
///
/// THE TOOL BODIES ARE NOT REIMPLEMENTED HERE. `GmPenTools.call` runs the same
/// `Tool` values the stdio door runs, so the roster, the per-tool `narrowing`,
/// the `degrade` re-runs and `PenResultBudget` all behave identically on both
/// doors. An earlier draft of this handler mapped tool names to `MessageType`s
/// and forwarded them; that quietly dropped the composites, the narrowing
/// advice and the degrade paths, which is most of what makes the pen usable
/// when a result is large.
enum McpCallHandler {

    static func handle(
        line: Data,
        head: EnvelopeHead,
        store: Store,
        caller: any GmVerbCaller
    ) throws -> HandlerResult {
        let req = try decodePayload(McpCallRequest.self, from: line)

        // ONE BOUNDARY FOR THE WHOLE TOOL, composite or not. A 1:1 tool gets a
        // transaction of one verb, which costs nothing and means the composite
        // and non-composite paths cannot drift in their atomicity.
        //
        // The two families that REFUSE to compose — `checkpointTruncate`, and
        // the four-phase repo verbs whose phase 3 does filesystem work holding
        // no db lock — throw `StoreError.notComposable` from inside. That
        // propagates and rolls back, which is the designed behaviour: a refusal
        // in five places beats an enrolment table listing which of ~230 verbs
        // are composable, and it must not be caught and swallowed here.
        var rendered = ""
        var toolFailed: String?
        do {
            try store.inTransaction {
                rendered = try GmPenTools.call(
                    tool: req.tool, arguments: req.arguments, caller: caller)
            }
        } catch let error as GmPenToolError {
            // An unknown tool is a CALLER mistake, not a kernel fault, and the
            // error text already names how to find the real roster. This is the
            // runtime half of the bidirectional name-parity check: the build
            // gate stops a plugin shipping a name nothing serves, and this
            // catches an OLDER cached plugin reaching a NEWER kernel, which the
            // gate cannot see.
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
            type: .mcpCall, requestId: head.requestId, ok: true, payload: response)
        return HandlerResult(line: try NDJSON.encodeLine(envelope))
    }
}
