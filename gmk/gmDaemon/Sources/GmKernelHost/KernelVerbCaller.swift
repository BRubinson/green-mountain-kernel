import Foundation
import GmDaemonSdk

/// `GmVerbCaller` satisfied WITHOUT a socket, by re-entering the dispatcher the
/// kernel already runs.
///
/// THE POINT: MCP tool bodies and hook bodies were written against
/// `DaemonClient`. Run them unchanged inside the kernel and each one dials the
/// daemon it is already running in — a self-connection, queued behind the very
/// call that would have to service it. That is a deadlock, not a slow path.
///
/// Rather than retype ~110 verb methods against a second in-process client, the
/// facade moved to `GmVerbCaller` (one line) and this conforms to it by
/// ENCODING the same envelope those methods build and handing it to
/// `Server.dispatch`. So all 96 handlers are reached exactly as a socket client
/// reaches them — same decode, same guards, same error envelopes — with the
/// socket hop removed.
///
/// RE-ENTRANCY IS ALREADY THE NORM HERE. `dispatch` is a pure `Data -> Data`
/// function holding no per-call state, and `TX_BATCH` already re-enters it once
/// per inner line. This adds a second caller to an entry point built for
/// exactly that.
///
/// WHY IT COMPOSES INSIDE A TRANSACTION. `StoreBoundary` is ambient and
/// RE-ENTRANT, so a verb reached through here while a boundary is open enlists
/// in that boundary instead of opening its own. That is the property the whole
/// harness envelope was for: a tool body that writes N rows writes them in ONE
/// transaction. It holds only while the verb layer performs no thread hops
/// inside a boundary — the ambient handle is thread-local. There are zero such
/// hops today and this file adds none. If you add one, remove the hop; do not
/// relax the boundary.
///
/// NOT AN ERROR PATH. A handler that fails reports it in its own `ok: false`
/// envelope, and `request` below turns that back into a thrown `StoreError`
/// exactly as `DaemonClient` does — so a caller cannot tell the two apart, which
/// is the whole contract.
struct KernelVerbCaller: GmVerbCaller {

    /// Injected rather than reached through a stored `Server`, matching what
    /// `TxBatchHandler` already does — it keeps this testable without standing
    /// up a socket, and it keeps the retain cycle out.
    let dispatch: (Data) -> HandlerResult

    func request<Req: Codable & Sendable, Resp: Codable & Sendable>(
        type: MessageType,
        payload: Req,
        responseType: Resp.Type
    ) throws -> Resp {
        let line = try NDJSON.encodeLine(RequestEnvelope(type: type, payload: payload))
        let result = dispatch(line)
        let response = try NDJSON.decode(ResponseEnvelope<Resp>.self, from: result.line)

        // The failure arms below are a DELIBERATE MIRROR of `DaemonClient.request`,
        // down to the error cases and the message. A caller reached through this
        // type must not be able to tell it from a socket call — including when
        // things go wrong, which is exactly when a divergence would be found the
        // hard way. `payload` being optional on the envelope is what lets one
        // decode serve both the success and failure shapes.
        if let error = response.error {
            if error.code == .protocolMismatch {
                throw DaemonClientError.protocolMismatch(
                    message: error.message, daemonVersion: error.daemonProtocolVersion)
            }
            throw DaemonClientError.server(error)
        }
        guard let payload = response.payload else {
            throw DaemonClientError.wire("response for \(type.rawValue) carried no payload")
        }
        return payload
    }
}
