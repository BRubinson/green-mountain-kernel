import Foundation

/// The one requirement behind the entire typed verb facade. Hanging
/// `DaemonClient+API.swift`'s ~110 one-liners off this PROTOCOL rather than
/// off `DaemonClient` gives the whole typed surface to any conformer, which is
/// what lets MCP and hook bodies run kernel-side instead of dialing the daemon
/// they are already inside — a self-connection on the serial queue that would
/// have to service it is a deadlock, not a slow path.

/// DELIBERATELY NOT ASYNC. The kernel's verb layer performs no thread hops
/// inside a transaction boundary, and that is what makes the ambient
/// thread-local `StoreBoundary` correct. An `async` requirement here would
/// invite an `await` inside a boundary and silently break it.
///
/// SENDABLE IS A REQUIREMENT, not decoration: the app trampolines every verb
/// from MainActor onto a serial queue, so a caller crosses executors by design.
protocol GmVerbCaller: Sendable {
    /// One request/response round-trip, however the conformer gets there —
    /// over the unix socket, or in-process against the store it already holds.
    func request<Req: Codable & Sendable, Resp: Codable & Sendable>(
        type: MessageType,
        payload: Req,
        responseType: Resp.Type
    ) throws -> Resp
}

/// The socket conformance. `DaemonClient.request` already has exactly this
/// shape, so the conformance is empty — which is the evidence that the protocol
/// was extracted from the real signature rather than designed alongside it.
extension DaemonClient: GmVerbCaller {}
