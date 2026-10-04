import Foundation

/// Encodes a success response envelope for a handler.
///
/// Shared success-envelope encoding for the per-message handler enums.
///
/// - Parameters:
///   - type: The message type for the response.
///   - head: The envelope head with protocol version and request id.
///   - payload: The response payload.
/// - Returns: The handler result with the encoded response.
/// - Throws: Encoding errors if the payload cannot be encoded.
func okResult<P: Codable & Sendable>(
    _ type: MessageType,
    _ head: EnvelopeHead,
    _ payload: P
) throws -> HandlerResult {
    let envelope = ResponseEnvelope<P>(type: type, requestId: head.requestId, ok: true, payload: payload)
    return HandlerResult(line: try NDJSON.encodeLine(envelope))
}

/// Decodes the typed payload from a request line.
///
/// - Parameters:
///   - _: The payload type to decode.
///   - line: The NDJSON line containing the request envelope.
/// - Returns: The decoded payload.
/// - Throws: `DecodingError` if the payload is malformed.
func decodePayload<P: Codable & Sendable>(_: P.Type, from line: Data) throws -> P {
    try NDJSON.decode(RequestEnvelope<P>.self, from: line).payload
}
