import Foundation
import GmDaemon
import GmDaemonSdk

/// `TX_BATCH` — N inner request lines, ONE transaction.
///
/// ## What this buys, and why it is not the ruled-out refactor
///
/// The shared-service-layer work gives in-process callers real transaction
/// scope. The relayed MCP surface could not have it: every tool call arrives as
/// its own wire message, so twelve `EXPLORE_FINDING_ADD` calls are twelve
/// commits, and a failure at the seventh leaves six rows behind in an
/// append-only history that cannot take them back.
///
/// Retyping the 96 handlers to a typed in-process signature was deliberately
/// deferred, and calling handlers from an in-process caller is ruled out
/// precisely because they are welded to JSON. This handler is not that. It has
/// no in-process caller: it arrives on the socket as one message whose payload
/// *is* request lines, and it re-enters `Server.dispatch(line:from:)` — which
/// the server already does once per connection. The JSON welding that blocks
/// in-process composition is the very thing that makes the batch trivial here:
/// the envelope needs no knowledge of what it carries.
///
/// ## Scope, stated so it is not over-read
///
/// This gives one TOOL BODY atomicity. It deliberately does not span an agent's
/// conversational sequence — propose, think, decide — because that is not a
/// transaction: the agent's next call is chosen from the previous *committed*
/// result, and an LLM turn is unbounded. A session-scoped `TX_BEGIN`/`TX_COMMIT`
/// would park the single `DatabaseQueue` writer across model latency and stall
/// every hook write in the machine, and a crashed client would leak the write
/// lock with no owner to release it. That design is rejected on purpose.
enum TxBatchHandler {

    /// Verbs that may never appear inside a batch.
    ///
    /// A DENY-list of 5 rather than an allow-list of ~230: an allow-list would
    /// need an entry per verb and would silently omit every verb added later,
    /// which fails in the permissive direction. Each of these five is excluded
    /// for a mechanical reason, not a cautious one:
    ///
    /// - `hello` is the handshake; it is not a db operation at all.
    /// - `subscribe` registers its sink DIRECTLY rather than via `queue.async`,
    ///   which is what makes replay-then-register gapless. Running it inside a
    ///   batch would move that registration inside a transaction and open the
    ///   window it exists to close.
    /// - `shutdown` ends the process. A batch member that terminates the server
    ///   mid-transaction cannot commit and cannot report.
    /// - `backup` uses GRDB's `backup(to:)` on the queue itself, outside any
    ///   transaction by construction.
    /// - `txBatch` itself: no nesting. The boundary would enlist happily, but a
    ///   nested batch makes `failedIndex` ambiguous about which level failed.
    /// - `mcpCall` and `hookEvent` (v30): both DISPATCH ANOTHER VERB, so either
    ///   one is a nesting alias. An `MCP_CALL` naming a batched tool expands
    ///   into a `TX_BATCH`, which would defeat the no-nesting rule above by
    ///   going through a different door — the deny on `txBatch` only stops the
    ///   direct spelling. This is the whole reason a deny-list has to be
    ///   maintained as new verbs land rather than written once.
    static let denied: Set<MessageType> = [
        .hello, .subscribe, .shutdown, .backup, .txBatch, .mcpCall, .hookEvent,
    ]

    /// Runs every inner line inside one transaction.
    ///
    /// `dispatch` is injected rather than reached through a stored `Server`
    /// reference so this stays testable without standing up a socket.
    static func handle(
        line: Data,
        head: EnvelopeHead,
        store: Store,
        dispatch: (Data) -> HandlerResult
    ) throws -> HandlerResult {
        let req = try decodePayload(TxBatchRequest.self, from: line)

        guard !req.requests.isEmpty else {
            throw StoreError.badRequest(detail: "TX_BATCH carried no requests")
        }

        // Validate the whole batch BEFORE opening the transaction. A denied
        // verb is a caller mistake, and refusing it without having written
        // anything is cheaper to reason about than a rollback.
        for (i, inner) in req.requests.enumerated() {
            guard let data = inner.data(using: .utf8) else {
                throw StoreError.badRequest(detail: "TX_BATCH request \(i) is not valid UTF-8")
            }
            let peek = try? NDJSON.decode(RawEnvelopeHead.self, from: data)
            guard let type = peek?.type else {
                throw StoreError.badRequest(
                    detail: "TX_BATCH request \(i) has an unknown or missing message type")
            }
            guard !denied.contains(type) else {
                throw StoreError.badRequest(
                    detail: "TX_BATCH request \(i) is \(type.rawValue), which cannot appear in a batch")
            }
        }

        // Results are buffered and emitted only after the commit, so a partial
        // batch is not observable even though the inner handlers each produced
        // their line as they ran.
        var buffered: [String] = []
        var failed: Int?

        do {
            try store.inTransaction {
                for (i, inner) in req.requests.enumerated() {
                    let data = Data(inner.utf8)
                    let result = dispatch(data)
                    let text = String(decoding: result.line, as: UTF8.self)

                    // An inner handler reports failure in its envelope rather
                    // than by throwing, so the envelope is what decides whether
                    // the transaction survives. Without this check a batch
                    // containing a VERSION_CONFLICT would COMMIT the rows
                    // around it and report success — the exact silent partial
                    // write the verb exists to prevent.
                    if let ok = try? NDJSON.decode(ResponseEnvelopeOK.self, from: result.line),
                       ok.ok == false {
                        failed = i
                        throw StoreError.badRequest(
                            detail: "TX_BATCH rolled back at request \(i): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                    buffered.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        } catch {
            // THROW, do not hand-build an `ok: false` envelope.
            //
            // This is the correctness bug this handler shipped with, caught by
            // review against a running kernel: an envelope with `ok: false` and
            // `error: nil` is read by `DaemonClient.call` as SUCCESS, because the
            // client branches on `response.error` rather than on `ok`. A
            // rolled-back batch therefore returned exit 0 with an empty result —
            // the rollback was correct and the report was a lie, which is worse
            // than either failing or succeeding outright.
            //
            // Throwing routes through the same path every other handler uses, so
            // the index-naming message actually reaches the caller. The
            // pre-transaction rejections above always worked for exactly this
            // reason; they throw.
            if let index = failed {
                throw StoreError.badRequest(
                    detail: "TX_BATCH rolled back at request \(index) — NOTHING was written. "
                        + "Underlying: \(error)")
            }
            throw error
        }

        return try okResult(.txBatch, head, TxBatchResponse(results: buffered))
    }
}

/// Minimal shape for reading only the `ok` flag off an inner result envelope,
/// whose payload type is not known here and deliberately stays unparsed.
private struct ResponseEnvelopeOK: Codable {
    let ok: Bool
}
