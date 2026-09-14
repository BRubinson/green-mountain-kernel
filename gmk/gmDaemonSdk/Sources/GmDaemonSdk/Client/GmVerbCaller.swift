import Foundation

/// The one requirement behind the entire typed verb facade.
///
/// `DaemonClient+API.swift` is ~110 methods and every single one has the same
/// body — `try request(type:payload:responseType:)` and nothing else. It is a
/// pure facade over one generic call. Hoisting that call into a protocol and
/// hanging the facade off the PROTOCOL rather than off `DaemonClient` hands the
/// whole typed surface to any conformer for the cost of one `extension` line.
///
/// WHY THIS EXISTS (v30): the harness envelope moves MCP tool bodies and hook
/// bodies kernel-side, where `inTransaction` is reachable. Those bodies were
/// written against `DaemonClient` — a SOCKET client. Run them unchanged inside
/// the kernel and each one dials the daemon it is already running in: a
/// self-connection, on the serial queue that would have to service it, which is
/// a deadlock rather than a slow path.
///
/// The alternative to this protocol was retyping ~110 call sites against a
/// second in-process client, or threading an `isLocal` flag through all of them.
/// Both are the deferred 96-handler retype wearing a different hat. This is one
/// line in `DaemonClient+API.swift` (`extension DaemonClient` →
/// `extension GmVerbCaller`) plus this file.
///
/// DELIBERATELY NOT ASYNC. `DaemonClient.request` is synchronous and serialized
/// on an internal lock; the kernel's own verb layer performs no thread hops
/// inside a transaction boundary, and that property is what makes the ambient
/// thread-local `StoreBoundary` correct. An `async` requirement here would
/// invite an `await` inside a boundary and silently break it — the invariant
/// `TransactionBoundaryTests` used to pin before it was deleted. Keep it sync.
/// SENDABLE IS A REQUIREMENT, not decoration. A caller is handed across
/// executors by design — the app trampolines every verb from MainActor onto a
/// serial queue, because the verb layer is synchronous and a write against a
/// large FTS database would otherwise stall the UI. `DaemonClient` is already
/// `Sendable` (its state is one fd behind a lock) and the kernel's in-process
/// caller is a struct holding one closure, so this constrains nothing that
/// existed; it just stops the next conformer from being the one that is not.
public protocol GmVerbCaller: Sendable {
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
