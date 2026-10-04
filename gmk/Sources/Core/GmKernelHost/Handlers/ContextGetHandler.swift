import Foundation

/// CONTEXT_GET — read-only resolution of the current gmcc environment.
///
/// Never creates rows.
enum ContextGetHandler {
    /// Handles a context get request.
    ///
    /// - Parameters:
    ///   - line: The encoded request line.
    ///   - head: The message envelope header.
    ///   - store: The application store.
    /// - Returns: The handler result with response.
    /// - Throws: Wire or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ContextGetRequest.self, from: line)
        return try okResult(.contextGet, head, try store.getContext(request))
    }
}
