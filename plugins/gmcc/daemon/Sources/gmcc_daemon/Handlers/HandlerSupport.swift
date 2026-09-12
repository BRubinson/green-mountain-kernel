import Foundation
import GMCCDaemonKit

/// Shared success-envelope encoding for the per-message handler enums.
func okResult<P: Codable & Sendable>(
    _ type: MessageType,
    _ head: EnvelopeHead,
    _ payload: P
) throws -> HandlerResult {
    let envelope = ResponseEnvelope<P>(type: type, requestId: head.requestId, ok: true, payload: payload)
    return HandlerResult(line: try NDJSON.encodeLine(envelope))
}

/// Decode the typed request payload for a handler.
func decodePayload<P: Codable & Sendable>(_ type: P.Type, from line: Data) throws -> P {
    try NDJSON.decode(RequestEnvelope<P>.self, from: line).payload
}
