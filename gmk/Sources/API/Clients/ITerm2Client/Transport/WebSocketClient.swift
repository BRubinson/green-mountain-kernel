import Foundation
import Security

final class WebSocketClient {
    private let socket: SocketConnection

    /// Initializes a WebSocket client with a socket connection.
    ///
    /// - Parameter socket: The underlying socket to send and receive frames on.
    init(socket: SocketConnection) {
        self.socket = socket
    }

    /// Performs the WebSocket handshake with iTerm2.
    ///
    /// Sends HTTP upgrade headers and verifies the server responds with a 101 status.
    /// May include optional authentication cookie and api key headers.
    ///
    /// - Parameters:
    ///   - cookie: Optional iTerm2 authentication cookie.
    ///   - key: Optional iTerm2 authentication key.
    /// - Throws: `ITerm2Error.handshakeFailed` or `apiDisabled` on failure.
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
            "x-iterm2-library-version: swift 1.0",
            "x-iterm2-advisory-name: GMVibes",
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
            if responseStr.contains("401") {
                throw .apiDisabled
            }
            throw .handshakeFailed(status: String(responseStr.prefix(200)))
        }
    }

    /// Sends binary data in a WebSocket frame.
    ///
    /// Encodes the data with masking key and length encoding per RFC 6455.
    ///
    /// - Parameter data: The binary payload to send.
    /// - Throws: `ITerm2Error` on socket send failure.
    func sendBinary(_ data: Data) throws(ITerm2Error) {
        var frame = Data()
        frame.reserveCapacity(14 + data.count)

        frame.append(0x82)

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

    /// Receives binary data from the WebSocket.
    ///
    /// Continues receiving frames until a data frame (not a control frame) arrives.
    ///
    /// - Returns: The received binary payload.
    /// - Throws: `ITerm2Error` on socket receive failure or frame errors.
    func receiveBinary() throws(ITerm2Error) -> Data {
        while true {
            if let payload = try receiveOneFrame() { return payload }
        }
    }

    /// Receives and parses one WebSocket frame.
    ///
    /// Handles masking, extended payload length encoding, and control frames (close, ping).
    /// Responds to ping frames with pong and returns nil; returns payload data for data frames.
    ///
    /// - Returns: The frame payload for data frames, nil for ping control frames.
    /// - Throws: `ITerm2Error` on socket errors or unrecognized opcodes.
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

        if opcode == 0x08 {
            throw .transportFailed(reason: "iTerm2 closed the WebSocket connection", errno: nil)
        }
        if opcode == 0x09 {
            try sendPong(payload)
            return nil
        }

        return payload
    }

    /// Closes the WebSocket connection.
    ///
    /// Sends a close frame and disconnects the underlying socket.
    func disconnect() {
        var closeFrame = Data([0x88, 0x80])
        closeFrame.append(contentsOf: [0, 0, 0, 0])
        try? socket.send(closeFrame)
        socket.disconnect()
    }

    /// Sends a WebSocket pong (control) frame in response to a ping.
    ///
    /// - Parameter payload: The ping payload to echo back.
    /// - Throws: `ITerm2Error.transportFailed` if payload exceeds 125 bytes.
    private func sendPong(_ payload: Data) throws(ITerm2Error) {
        guard payload.count <= 125 else {
            throw .transportFailed(
                reason: "Oversized WebSocket control frame: \(payload.count) bytes",
                errno: nil
            )
        }

        var frame = Data()
        frame.append(0x8A)
        frame.append(UInt8(payload.count) | 0x80)
        let maskKey = Self.randomBytes(4)
        frame.append(contentsOf: maskKey)
        for (i, byte) in payload.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }
        try socket.send(frame)
    }

    /// Generates a random WebSocket key for the handshake.
    ///
    /// - Returns: A base64-encoded 16-byte random value.
    private static func generateSecWebSocketKey() -> String {
        Data(randomBytes(16)).base64EncodedString()
    }

    /// Generates random bytes using the system entropy source.
    ///
    /// Falls back to `UInt8.random` if `SecRandomCopyBytes` fails.
    ///
    /// - Parameter count: The number of random bytes to generate.
    /// - Returns: An array of random bytes.
    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes
    }
}
