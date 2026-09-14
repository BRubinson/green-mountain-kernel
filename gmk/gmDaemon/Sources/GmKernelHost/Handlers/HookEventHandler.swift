import Foundation
import GmDaemon
import GmDaemonSdk

/// `HOOK_EVENT` — one Claude Code lifecycle hook, served by the kernel.
///
/// THE CALL SITE MOVED, NOT THE LOGIC. `HookLogic` and `HookRunner` already
/// compile into this binary (they live in `GmDaemonSdk/Hook/`), and
/// `HookRunner.postToolUse` already takes its cwd from the PAYLOAD rather than
/// from the process — which is exactly what a hook served by a long-lived
/// kernel needs, since the kernel's own cwd is meaningless here. So this verb
/// re-points those functions at the in-process caller instead of relocating
/// ~957 lines.
///
/// THE LAUNCHER STAYS A SHELL-FORM `command` HOOK. That is not a half-measure,
/// it is what the harness permits: `SessionStart` accepts only `command` and
/// `mcp_tool`, never `http`; an `mcp_tool` handler there is documented to
/// expect a "not connected" error on first run; and `SessionStart` is precisely
/// where the claude-session binding every later write depends on gets created.
/// Shell form is additionally the only handler type that resolves
/// `${GM_FS_ROOT:-$HOME/gmfs}` at hook time and the only one that can honour the
/// silent exit-0 no-op contract. `async` is command-only too, which is what
/// keeps `PostToolUse` off the tool-call critical path.
///
/// WHY `hookSafe` IS ON THE WIRE. A hook may never exit non-zero — a non-zero
/// `PostToolUse` is a BLOCKED tool call — and `gm_hook call` exits non-zero on
/// error. Making the contract part of the message means a caller cannot forget
/// it and the daemon cannot answer the wrong way by accident. Under it, a
/// BUSINESS failure comes back `ok: true` with the reason in `note`; framing and
/// decode failures still throw, because those are not business failures and
/// swallowing them would hide a broken client forever.
enum HookEventHandler {

    static func handle(
        line: Data,
        head: EnvelopeHead,
        store: Store,
        caller: any GmVerbCaller
    ) throws -> HandlerResult {
        let req = try decodePayload(HookEventRequest.self, from: line)

        var response: HookEventResponse
        do {
            response = try run(req, caller: caller, store: store)
        } catch {
            // The `hookSafe` contract, honoured in exactly one place.
            //
            // The failure is REPORTED, never merely dropped: a swallowed error
            // that says nothing anywhere is how a hook silently stops recording
            // and nobody notices for weeks. `note` is where it lands, and the
            // response is still `recorded: false` so a reader can tell the
            // difference between "nothing to do" and "tried and failed".
            guard req.hookSafe else { throw error }
            response = HookEventResponse(
                recorded: false,
                note: "hook '\(req.event)' failed and was suppressed by hook_safe: \(error)")
        }

        let envelope = ResponseEnvelope<HookEventResponse>(
            type: .hookEvent, requestId: head.requestId, ok: true, payload: response)
        return HandlerResult(line: try NDJSON.encodeLine(envelope))
    }

    /// Routes one event to the logic that already exists for it.
    ///
    /// `event` is matched as a RAW STRING rather than decoded into an enum. The
    /// harness owns this vocabulary and grows it — there are 30 lifecycle events
    /// today and the list moves — so an unknown event must be a recorded no-op,
    /// never a decode failure. A hook manifest that fires something this build
    /// does not handle should cost nothing; refusing it would turn a harness
    /// upgrade into a broken session.
    private static func run(
        _ req: HookEventRequest,
        caller: any GmVerbCaller,
        store: Store
    ) throws -> HookEventResponse {
        // The hook functions parse the harness's own JSON shape, so the payload
        // is handed back to them as bytes rather than re-modelled here. That
        // keeps ONE parser for the hook wire format — `HookPayload.decode` —
        // instead of a second one on this side that could disagree about, say,
        // which key carries the session id.
        let payloadData: Data
        if let payload = req.payload {
            payloadData = try JSONEncoder().encode(payload)
        } else {
            payloadData = Data("{}".utf8)
        }

        switch req.event {
        case "PostToolUse":
            // Writes ride the ambient boundary: one tool call can name several
            // written paths, and those rows belong together or not at all.
            try store.inTransaction {
                _ = HookRunner.postToolUse(stdin: payloadData, dryRun: false, caller: caller)
            }
            return HookEventResponse(recorded: true)

        case "SubagentStart":
            var context: String?
            try store.inTransaction {
                context = HookRunner.subagentStart(
                    stdin: payloadData, dryRun: false,
                    sheetText: PenSheet.instructions, caller: caller)
            }
            return HookEventResponse(
                recorded: true, additionalContext: context)

        default:
            // Recorded as a no-op, deliberately. See the doc comment above.
            return HookEventResponse(
                recorded: false,
                note: "no kernel-side handler for hook event '\(req.event)' — ignored")
        }
    }
}
