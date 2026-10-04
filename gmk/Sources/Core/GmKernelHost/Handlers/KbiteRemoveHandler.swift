import Foundation

/// KBITE_REMOVE — drop a kbite from one scope's registry.
///
/// Db only.
enum KbiteRemoveHandler {
    /// Handles a kbite remove request to drop a kbite from the registry.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the response.
    /// - Throws: A handler error if the request is invalid or the operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteRemoveRequest.self, from: line)
        return try okResult(.kbiteRemove, head, try store.removeKbite(request))
    }
}
