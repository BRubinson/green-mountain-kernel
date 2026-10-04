import Foundation

/// INSTANCE_CURRENT_SESSION — the session matching the instance's checked-out branch, or none.
enum InstanceCurrentSessionHandler {
    /// Handles an INSTANCE_CURRENT_SESSION verb request from the wire.
    ///
    /// - Parameters:
    ///   - line: The verb line payload data.
    ///   - head: The envelope header containing request metadata.
    ///   - store: The store instance to query the current session from.
    /// - Returns: A handler result with the current session response.
    /// - Throws: `HandlerError` errors if decoding or query fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(InstanceCurrentSessionRequest.self, from: line)
        return try okResult(.instanceCurrentSession, head, try store.instanceCurrentSession(request))
    }
}
