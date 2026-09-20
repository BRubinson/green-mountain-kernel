import Foundation

/// `HOOK_EVENT` — one Claude Code lifecycle hook, served by the kernel. It
/// re-points `HookLogic` / `HookRunner` at the in-process caller; those take
/// their cwd from the PAYLOAD, since the kernel's own cwd is meaningless here.
///
/// `hookSafe` rides the wire because a hook may never exit non-zero — a
/// non-zero `PostToolUse` is a BLOCKED tool call. Under it a BUSINESS failure
/// answers `ok: true` with the reason in `note`; framing and decode failures
/// still throw, since swallowing those hides a broken client forever.
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
            // The `hookSafe` contract, honoured in exactly one place. The
            // failure is REPORTED in `note`, never merely dropped, and
            // `recorded: false` keeps "nothing to do" distinguishable from
            // "tried and failed".
            guard req.hookSafe else { throw error }
            response = HookEventResponse(
                recorded: false,
                note: "hook '\(req.event)' failed and was suppressed by hook_safe: \(error)"
            )
        }

        let envelope = ResponseEnvelope<HookEventResponse>(
            type: .hookEvent,
            requestId: head.requestId,
            ok: true,
            payload: response
        )
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
                    stdin: payloadData,
                    dryRun: false,
                    sheetText: CdeSheet.instructions,
                    caller: caller
                )
            }
            return HookEventResponse(
                recorded: true,
                additionalContext: context
            )

        default:
            // Recorded as a no-op, deliberately. See the doc comment above.
            return HookEventResponse(
                recorded: false,
                note: "no kernel-side handler for hook event '\(req.event)' — ignored"
            )
        }
    }
}
