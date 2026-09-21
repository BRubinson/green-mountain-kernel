import Foundation
import SwiftProtobuf

final class APIClient {
    private let ws: WebSocketClient
    private var requestId: Int64 = 0

    private init(ws: WebSocketClient) {
        self.ws = ws
    }

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

    func nextId() -> Int64 {
        requestId += 1
        return requestId
    }

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

    func disconnect() {
        ws.disconnect()
    }
}
