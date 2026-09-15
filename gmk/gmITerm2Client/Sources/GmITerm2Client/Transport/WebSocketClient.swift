import Foundation
import Security

/// Minimal WebSocket client over a raw socket connection.
///
/// Lifted from `it2cli/Sources/it2/Transport/WebSocketClient.swift`. Just
/// enough of RFC 6455 for binary message exchange with iTerm2: binary frames
/// only, client masking always on, ping answered with pong, close surfaced as a
/// failure.
///
/// TWO CHANGES from upstream, and only two:
///
///  1. The advisory headers are ours. `x-iterm2-advisory-name` and
///     `x-iterm2-library-version` are what iTerm2 shows a human in its
///     connection-approval UI, so they must say GMVibes rather than `it2`.
///  2. The handshake's status mapping throws `ITerm2Error`. Upstream ALREADY
///     special-cased 401 with an "enable the Python API" message — that branch
///     is wired through as `.apiDisabled` rather than reinvented, because it is
///     precisely the enablement affordance this design owes the user.
///
/// **NOT `Sendable`, ON PURPOSE** — see the note on `SocketConnection`.
final class WebSocketClient {
    private let socket: SocketConnection

    init(socket: SocketConnection) {
        self.socket = socket
    }

    /// Perform the HTTP upgrade handshake.
    func handshake(cookie: String?, key: String?) throws(ITerm2Error) {
        let secKey = Self.generateSecWebSocketKey()

        var headers = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: \(secKey)",
            "Sec-WebSocket-Protocol: api.iterm2.com",
            "Origin: ws://localhost/",
            // EXACTLY TWO SPACE-SEPARATED PARTS, "<name> <version>". This is a
            // PARSED field, not a free-form banner: `iTermWebSocketConnection.m`
            // splits it on spaces and rejects the whole handshake with 400 Bad
            // Request unless `parts.count == 2`. A third token here — e.g.
            // "swift gmvibes 1.0" — fails EVERY connection, and the error
            // surfaces as a bare "400 Bad Request" that names nothing.
            // Our identity belongs in the advisory-name header below, which IS
            // free-form and IS what iTerm2 shows in its approval UI.
            "x-iterm2-library-version: swift 1.0",
            "x-iterm2-advisory-name: GMVibes",
            // KEEP THIS. With the auth UI disabled a rejection comes back to US
            // as a 401 we can report. With it enabled, iTerm2 parks on a modal
            // inside its own window — and under `LSUIElement = YES` GMVibes has
            // no Dock icon, so the user has nothing to click back to and the
            // launch simply appears to hang.
            "x-iterm2-disable-auth-ui: true",
        ]

        if let cookie { headers.append("x-iterm2-cookie: \(cookie)") }
        if let key { headers.append("x-iterm2-key: \(key)") }

        let request = headers.joined(separator: "\r\n") + "\r\n\r\n"
        try socket.send(Data(request.utf8))

        let headerEnd = Data("\r\n\r\n".utf8)
        let responseData = try socket.recvUntil(headerEnd)

        guard let responseStr = String(data: responseData, encoding: .utf8) else {
            throw .handshakeFailed(status: "non-UTF-8 HTTP response from iTerm2")
        }

        guard responseStr.contains("101") else {
            // Upstream's 401 branch, retyped. This is the ONE failure a human
            // can actually fix, and it has a specific case so the UI can say
            // where the switch is.
            if responseStr.contains("401") {
                throw .apiDisabled
            }
            throw .handshakeFailed(status: String(responseStr.prefix(200)))
        }
    }

    /// Send a binary WebSocket frame.
    func sendBinary(_ data: Data) throws(ITerm2Error) {
        // Header (2-10 bytes) + mask (4 bytes) + payload.
        var frame = Data()
        frame.reserveCapacity(14 + data.count)

        // FIN + binary opcode.
        frame.append(0x82)

        // Mask bit always set for client frames, then the payload length.
        let length = data.count
        if length < 126 {
            frame.append(UInt8(length) | 0x80)
        } else if length < 65_536 {
            frame.append(126 | 0x80)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127 | 0x80)
            for i in (0..<8).reversed() {
                frame.append(UInt8((length >> (i * 8)) & 0xFF))
            }
        }

        let maskKey = Self.randomBytes(4)
        frame.append(contentsOf: maskKey)

        for (i, byte) in data.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }

        try socket.send(frame)
    }

    /// Receive a binary WebSocket frame. Returns the unmasked payload.
    ///
    /// A ping is answered and then the read is RETRIED IN THIS LOOP rather than
    /// by recursing. Recursion here would let a peer that pings faster than it
    /// sends data grow the stack without bound, and there is no natural limit
    /// to lean on — "how many pings are too many" is not a question this code
    /// should have to answer.
    func receiveBinary() throws(ITerm2Error) -> Data {
        while true {
            if let payload = try receiveOneFrame() { return payload }
        }
    }

    /// One frame. Returns nil when the frame was a ping that has been answered
    /// and the caller should read again.
    private func receiveOneFrame() throws(ITerm2Error) -> Data? {
        let header = try socket.recv(count: 2)
        let opcode = header[header.startIndex] & 0x0F
        let masked = (header[header.startIndex + 1] & 0x80) != 0
        var payloadLength = UInt64(header[header.startIndex + 1] & 0x7F)

        if payloadLength == 126 {
            let ext = try socket.recv(count: 2)
            payloadLength = UInt64(ext[ext.startIndex]) << 8 | UInt64(ext[ext.startIndex + 1])
        } else if payloadLength == 127 {
            let ext = try socket.recv(count: 8)
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = (payloadLength << 8) | UInt64(ext[ext.startIndex + i])
            }
        }

        // The server should not mask, but handle it if it does.
        var maskKey: [UInt8]?
        if masked {
            maskKey = [UInt8](try socket.recv(count: 4))
        }

        guard payloadLength <= 100_000_000 else {
            throw .transportFailed(
                reason: "WebSocket frame too large: \(payloadLength) bytes",
                errno: nil
            )
        }
        var payload = try socket.recv(count: Int(payloadLength))

        if let key = maskKey {
            for i in payload.indices {
                payload[i] ^= key[(i - payload.startIndex) % 4]
            }
        }

        if opcode == 0x08 { // Close
            throw .transportFailed(reason: "iTerm2 closed the WebSocket connection", errno: nil)
        }
        if opcode == 0x09 { // Ping — answer, then let the caller's loop read again.
            try sendPong(payload)
            return nil
        }

        return payload
    }

    func disconnect() {
        // Close frame, best effort: FIN + close opcode, masked, zero length.
        var closeFrame = Data([0x88, 0x80])
        closeFrame.append(contentsOf: [0, 0, 0, 0])
        try? socket.send(closeFrame)
        socket.disconnect()
    }

    // MARK: - Private

    private func sendPong(_ payload: Data) throws(ITerm2Error) {
        // RFC 6455 §5.5 caps a CONTROL frame payload at 125 bytes, and this
        // guard is why the narrowing below is safe. Without it, the peer picks
        // our failure mode: >255 makes `UInt8(_:)` fail its precondition and
        // TRAP — aborting the whole app, not throwing — and 126...255 writes a
        // value RFC 6455 reserves as an extended-length marker, mis-framing the
        // pong so the stream desynchronises from there on.
        //
        // Upstream omitted this because a CLI can afford to assume a
        // well-behaved peer and a crash costs one process exit. In a long-lived
        // GUI app it costs the user's session, so the cap is enforced HERE
        // rather than assumed of iTerm2.
        guard payload.count <= 125 else {
            throw .transportFailed(
                reason: "Oversized WebSocket control frame: \(payload.count) bytes",
                errno: nil
            )
        }

        var frame = Data()
        frame.append(0x8A) // FIN + pong
        frame.append(UInt8(payload.count) | 0x80) // masked
        let maskKey = Self.randomBytes(4)
        frame.append(contentsOf: maskKey)
        for (i, byte) in payload.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }
        try socket.send(frame)
    }

    private static func generateSecWebSocketKey() -> String {
        Data(randomBytes(16)).base64EncodedString()
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            // Masking is an RFC 6455 framing requirement, not a security
            // boundary on a unix socket we already authenticated over. A weaker
            // source here is survivable; failing the launch over it is not.
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes
    }
}
