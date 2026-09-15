import Foundation
import SwiftProtobuf

/// One authenticated conversation with iTerm2's API server.
///
/// A REDUCED lift of `it2cli/Sources/it2/Transport/APIClient.swift`. Kept:
/// `nextId()`, `send(_:)` including its id-discarding loop, and `disconnect()`.
///
/// Dropped: `resolveSessionId`, `normalizeSessionId`, and the focus-state /
/// `ListSessions` helpers. Slice 1 addresses no EXISTING session — it creates a
/// window and walks away — so none of that is reachable, and carrying dead
/// session-addressing code would imply a capability this package does not have.
///
/// Types are the SwiftProtobuf structs (`Iterm2_ClientOriginatedMessage` /
/// `Iterm2_ServerOriginatedMessage`), not upstream's Obj-C `ITM*` runtime.
///
/// **NOT `Sendable`, ON PURPOSE** — see the note on `SocketConnection`. It holds
/// a mutable `requestId` and blocks on `recv`.
final class APIClient {
    private let ws: WebSocketClient
    private var requestId: Int64 = 0

    private init(ws: WebSocketClient) {
        self.ws = ws
    }

    /// Connect, authenticate, and complete the upgrade handshake.
    static func connect() throws(ITerm2Error) -> APIClient {
        let socket = try SocketConnection.connect()
        let ws = WebSocketClient(socket: socket)

        let (cookie, key) = CookieAuth.credentials()
        // No cookie on this path means the Apple event was denied — see the
        // header of `CookieAuth`. Report that rather than letting the handshake
        // fail as an opaque 401 the user cannot distinguish from anything else.
        guard cookie != nil else {
            socket.disconnect()
            throw .automationDenied
        }

        do {
            try ws.handshake(cookie: cookie, key: key)
        } catch {
            socket.disconnect()
            throw error
        }

        return APIClient(ws: ws)
    }

    func nextId() -> Int64 {
        requestId += 1
        return requestId
    }

    /// Send one request and return the response carrying the same id.
    ///
    /// **THE ID-MATCHING LOOP IS SOUND ONLY BECAUSE THE OWNING ACTOR
    /// SERIALISES.** Notifications share this stream, so a frame arriving now
    /// need not be the answer to the question just asked, and the loop discards
    /// anything whose id does not match. That is CORRECT — rather than
    /// accidentally correct — precisely because exactly one request is ever in
    /// flight: `ITerm2Client` owns this object, an actor admits one caller at a
    /// time, and no one else can interleave a second request whose reply this
    /// loop would then swallow. Take the serialisation away and this becomes a
    /// race that returns another caller's answer.
    func send(_ request: Iterm2_ClientOriginatedMessage) throws(ITerm2Error) -> Iterm2_ServerOriginatedMessage {
        var request = request
        if request.id == 0 {
            request.id = nextId()
        }

        let data: Data
        do {
            data = try request.serializedData()
        } catch {
            throw .serverError("Failed to serialize request: \(error)")
        }

        try ws.sendBinary(data)

        let expectedId = request.id

        // AN ABSOLUTE DEADLINE OVER THE WHOLE LOOP, not just per read.
        // `SO_RCVTIMEO` bounds a SINGLE `recv(2)`, and every arriving frame
        // resets that window — so it protects against a SILENT server and not
        // against a CHATTY one. A peer emitting frames whose ids never match
        // would otherwise spin here forever: `createWindow` never returns, the
        // actor's dedicated thread stays occupied, and the UI sits on
        // "Connecting…" with no error and no timeout. Slice 1 subscribes to
        // nothing, so today only our own reply arrives — this bound exists so
        // that the first notification anyone adds later turns into a timeout
        // rather than a hang.
        let deadline = Date().addingTimeInterval(30)
        while true {
            guard Date() < deadline else {
                throw .responseLost(
                    reason: "No reply to request \(expectedId) within 30s"
                )
            }
            // THE SEND/RECEIVE ASYMMETRY IS LOAD-BEARING — do not collapse it.
            // A failure in `sendBinary` above means the request NEVER REACHED
            // iTerm2, so retrying it is safe. A failure HERE means the request
            // may already have been EXECUTED and only the answer was lost, so
            // retrying would perform it twice. `CreateTabRequest` is not
            // idempotent: a blind retry opens a second window running a second
            // `claude` against the same prompt. `.responseLost` is what stops
            // `createWindow`'s reconnect-once from doing that.
            let responseData: Data
            do {
                responseData = try ws.receiveBinary()
            } catch {
                throw .responseLost(reason: "\(error)")
            }
            let response: Iterm2_ServerOriginatedMessage
            do {
                response = try Iterm2_ServerOriginatedMessage(serializedBytes: responseData)
            } catch {
                throw .serverError("Failed to parse response: \(error)")
            }

            // ID GATE FIRST, then the error check. The other order lets an
            // error carried on SOMEONE ELSE'S frame abort our request, which
            // contradicts the "discard anything whose id does not match"
            // contract stated above.
            guard response.id == expectedId else {
                // A notification for a subscription we never made, or a reply
                // to a request that no longer has a caller. Discard it.
                continue
            }

            if case .error(let message)? = response.submessage {
                throw .serverError(message)
            }

            return response
            // Anything else is a notification for a subscription we never made,
            // or a reply to a request that no longer has a caller. Discard it.
        }
    }

    func disconnect() {
        ws.disconnect()
    }
}
