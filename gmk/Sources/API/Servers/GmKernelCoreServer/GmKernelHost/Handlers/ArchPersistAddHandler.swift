import Foundation

/// ARCH_PERSIST_ADD — add a persistence-layer change row (drafting only; path normalized).
enum ArchPersistAddHandler {
    /// Handles ARCH_PERSIST_ADD requests.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The kernel data store.
    /// - Returns: The handler result with the response.
    /// - Throws: An error if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchPersistAddRequest.self, from: line)
        return try okResult(.archPersistAdd, head, try store.archPersistAdd(request))
    }
}
