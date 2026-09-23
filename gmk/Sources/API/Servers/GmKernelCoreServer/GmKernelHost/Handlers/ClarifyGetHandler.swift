import Foundation

/// CLARIFY_GET — summary plus ordered clarification rows for a prompt.
enum ClarifyGetHandler {
    /// Handles a CLARIFY_GET request and returns the clarification response.
    ///
    /// - Parameters:
    ///   - line: The serialized request payload.
    ///   - head: The envelope header with request metadata.
    ///   - store: The data store to query.
    /// - Returns: The handler result containing the clarification response.
    /// - Throws: `EnvelopeError` or `StoreError` on decoding or data access failures.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyGetRequest.self, from: line)
        return try okResult(.clarifyGet, head, try store.clarifyGet(request))
    }
}
