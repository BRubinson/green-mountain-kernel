import Foundation

/// `GmVerbCaller` satisfied WITHOUT a socket, by re-entering the dispatcher the
/// kernel already runs: a tool or hook body that dialled the daemon it runs
/// inside would self-connect and deadlock behind its own call. It ENCODES the
/// same envelope `DaemonClient` builds and hands it to `Server.dispatch`, so
/// handlers see the same decode, the same guards and the same error envelopes.
///
/// `StoreBoundary` is ambient and RE-ENTRANT, so a verb reached here enlists in
/// an open boundary — true only while the verb layer makes no thread hops in one.
struct KernelVerbCaller: GmVerbCaller {

    /// Injected rather than reached through a stored `Server`: testable without
    /// standing up a socket, and no retain cycle. `@Sendable` because a caller
    /// genuinely crosses executors — the app hands this one from MainActor to
    /// the serial queue every verb call is trampolined onto — and it is safe to
    /// send because `Server.dispatch` holds no per-call state.
    let dispatch: @Sendable (Data) -> HandlerResult

    func request<Req: Codable & Sendable, Resp: Codable & Sendable>(
        type: MessageType,
        payload: Req,
        responseType _: Resp.Type
    ) throws -> Resp {
        let line = try NDJSON.encodeLine(RequestEnvelope(type: type, payload: payload))
        let result = dispatch(line)
        let response = try NDJSON.decode(ResponseEnvelope<Resp>.self, from: result.line)

        // The failure arms below MIRROR `DaemonClient.request`, down to the error
        // cases and the message: a caller must not be able to tell this type from
        // a socket call, least of all when things go wrong.
        if let error = response.error {
            if error.code == .protocolMismatch {
                throw DaemonClientError.protocolMismatch(
                    message: error.message,
                    daemonVersion: error.daemonProtocolVersion
                )
            }
            throw DaemonClientError.server(error)
        }
        guard let payload = response.payload else {
            throw DaemonClientError.wire("response for \(type.rawValue) carried no payload")
        }
        return payload
    }
}
