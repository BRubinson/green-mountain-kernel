import Foundation

/// KBITE_ADD — explicit-only registration at one scope.
///
/// Db only — no yaml
/// write-through (the interim yaml sync is the client skill's job).
enum KbiteAddHandler {
    /// Handles a kbite add request and returns the result.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header.
    ///   - store: The database store to add to.
    /// - Returns: The handler result containing the added kbite.
    /// - Throws: Any error during the add operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteAddRequest.self, from: line)
        return try okResult(.kbiteAdd, head, try store.addKbite(request))
    }
}
