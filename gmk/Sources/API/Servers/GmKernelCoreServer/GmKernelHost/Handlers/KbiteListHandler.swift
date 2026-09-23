import Foundation

/// KBITE_LIST — registry at a scope, resolved through the inheritance chain
/// at read time.
enum KbiteListHandler {
    /// Handles a kbite-list request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the kbite list.
    /// - Throws: Any decoding or store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteListRequest.self, from: line)
        return try okResult(.kbiteList, head, try store.listKbites(request))
    }
}
