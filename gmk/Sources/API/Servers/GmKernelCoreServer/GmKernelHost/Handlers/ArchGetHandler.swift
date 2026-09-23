import Foundation

/// ARCH_GET — summary plus ordered change rows, decorated with derived
/// implementation state, unplanned changes, and the persistence-first audit.
enum ArchGetHandler {
    /// Handle an ARCH_GET request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The persistence store.
    /// - Returns: A `HandlerResult` containing the encoded response.
    /// - Throws: `HandlerError` if decoding or processing fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchGetRequest.self, from: line)
        return try okResult(.archGet, head, try store.archGet(request))
    }
}
