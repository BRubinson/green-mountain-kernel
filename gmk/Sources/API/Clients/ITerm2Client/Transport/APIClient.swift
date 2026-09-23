import Foundation
import SwiftProtobuf

final class APIClient {
    private let ws: WebSocketClient
    private var requestId: Int64 = 0

    /// Creates an API client with an established websocket connection.
    ///
    /// - Parameter ws: The websocket client to use for communication.
    private init(ws: WebSocketClient) {
        self.ws = ws
    }

    /// Connect to the iTerm2 API server.
    ///
    /// - Returns: A connected API client ready to send requests.
    /// - Throws: `ITerm2Error.automationDenied` if credentials are unavailable; `ITerm2Error` for connection or handshake failures.
    static func connect() throws(ITerm2Error) -> APIClient {
        let socket = try SocketConnection.connect()
        let ws = WebSocketClient(socket: socket)

        let (cookie, key) = CookieAuth.credentials()
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

    /// Allocate the next unique request ID.
    ///
    /// - Returns: An incremented request ID.
    func nextId() -> Int64 {
        requestId += 1
        return requestId
    }

    /// Send a request to the server and wait for the matching response.
    ///
    /// Allocates a request ID if the request does not have one, serializes and sends it,
    /// then waits up to 30 seconds for the response with the same ID.
    ///
    /// - Parameter request: The client-originated message to send.
    /// - Returns: The server-originated response message.
    /// - Throws: `ITerm2Error` on serialization failure, timeout, or server error.
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

        let deadline = Date().addingTimeInterval(30)
        while true {
            guard Date() < deadline else {
                throw .responseLost(
                    reason: "No reply to request \(expectedId) within 30s"
                )
            }
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

            guard response.id == expectedId else {
                continue
            }

            if case .error(let message)? = response.submessage {
                throw .serverError(message)
            }

            return response
        }
    }

    /// Close the websocket connection to the server.
    func disconnect() {
        ws.disconnect()
    }
}
