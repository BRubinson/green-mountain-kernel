import Foundation

/// ARCH_FIELD_ADD — add a field-level row under a persistence change (drafting only).
enum ArchFieldAddHandler {
    /// Handles an archFieldAdd request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchFieldAddRequest.self, from: line)
        return try okResult(.archFieldAdd, head, try store.archFieldAdd(request))
    }
}
