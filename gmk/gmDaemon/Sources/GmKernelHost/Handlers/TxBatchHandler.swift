import Foundation
import GmDaemon
import GmDaemonSdk

/// `TX_BATCH` — N inner request lines, ONE transaction. A relayed tool call
/// otherwise arrives as its own wire message, so twelve writes are twelve
/// commits and a failure at the seventh leaves six rows in an append-only
/// history that cannot take them back. The payload IS request lines, re-entered
/// through `Server.dispatch(line:from:)`, so the envelope need not parse them.
///
/// Scope is ONE TOOL BODY. A session-scoped `TX_BEGIN`/`TX_COMMIT` is rejected:
/// it parks the single writer across model latency and leaks the lock on crash.
enum TxBatchHandler {

    /// Verbs that may never appear inside a batch — a DENY-list rather than an
    /// allow-list of ~230, which would silently omit every verb added later and
    /// so fail permissively. `hello` is not a db operation at all;
    /// `subscribe` registers its sink directly to stay gapless;
    /// `shutdown` ends the process mid-transaction; `backup` runs outside any
    /// transaction; `txBatch`, `mcpCall` and `hookEvent` each dispatch another
    /// verb, and nesting makes `failedIndex` ambiguous — new dispatching verbs
    /// belong here too.
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
                    detail: "TX_BATCH request \(i) has an unknown or missing message type"
                )
            }
            guard !denied.contains(type) else {
                throw StoreError.badRequest(
                    detail: "TX_BATCH request \(i) is \(type.rawValue), which cannot appear in a batch"
                )
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
                        ok.ok == false
                    {
                        failed = i
                        throw StoreError.badRequest(
                            detail:
                                "TX_BATCH rolled back at request \(i): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                        )
                    }
                    buffered.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        } catch {
            // THROW, never hand-build an `ok: false` envelope: `DaemonClient.call`
            // branches on `response.error` rather than on `ok`, so a hand-built
            // one reads as SUCCESS and a rolled-back batch reports exit 0 with an
            // empty result. Throwing routes through the path every other handler
            // uses, so the index-naming message reaches the caller.
            if let index = failed {
                throw StoreError.badRequest(
                    detail: "TX_BATCH rolled back at request \(index) — NOTHING was written. "
                        + "Underlying: \(error)"
                )
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
