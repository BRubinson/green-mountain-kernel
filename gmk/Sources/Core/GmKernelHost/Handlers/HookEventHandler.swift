import Foundation

/// `HOOK_EVENT` — one Claude Code lifecycle hook served by the kernel.
///
/// Re-points `GmHook` handlers at in-process caller; those take cwd from
/// PAYLOAD since kernel's cwd is meaningless here. `hookSafe` rides the wire
/// because hooks never exit non-zero (non-zero `PostToolUse` = BLOCKED tool).
/// A BUSINESS failure answers `ok: true` with reason in `note`; framing and
/// decode failures throw (swallowing hides broken client).
enum HookEventHandler {

    /// Handles a hook event request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    ///   - caller: The caller context for the hook operation.
    /// - Returns: A handler result with the response.
    /// - Throws: Any error from decoding the request or running the hook.
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

    /// Routes one event through the `GmHookEvent` registry.
    ///
    /// `event` rides the wire as a RAW STRING and is looked up here, never
    /// decoded: the harness owns this vocabulary and grows it, so an unknown
    /// event must be a recorded no-op rather than a decode failure that turns a
    /// harness upgrade into a broken session.
    /// - Parameters:
    ///   - req: The hook event request.
    ///   - caller: The caller context for the hook operation.
    ///   - store: The persistence store for the operation.
    /// - Returns: A response indicating whether the hook was recorded and any associated note.
    /// - Throws: Any error from running the hook.
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

        guard let event = GmHookEvent(rawValue: req.event) else {
            // Recorded as a no-op, deliberately. See the doc comment above.
            return HookEventResponse(
                recorded: false,
                note: "no kernel-side handler for hook event '\(req.event)' — ignored"
            )
        }

        // Writes ride the ambient boundary: one tool call can name several
        // written paths, and those rows belong together or not at all.
        var line: String?
        try store.inTransaction {
            line = event.hook.run(GmHookContext(stdin: payloadData, dryRun: false, caller: caller))
        }

        switch event {
        case .postToolUse:
            return HookEventResponse(recorded: true)
        case .subagentStart:
            return HookEventResponse(recorded: true, additionalContext: line)
        case .preToolUse:
            // A deny is a decision, not a write; the response line is the note.
            return HookEventResponse(recorded: false, note: line)
        }
    }
}
