import Foundation

/// DOPE_GET — full-tree read; PROMPT scope preferred, SESSION_INSTANCE fallback.
enum DopeGetHandler {
    /// Handles a dope tree read request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for this request.
    ///   - store: The store instance to query.
    /// - Returns: The handler result with the dope tree response.
    /// - Throws: `HandlerError` or `StoreError` if the request fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeGetRequest.self, from: line)
        return try okResult(.dopeGet, head, try store.dopeGet(request))
    }
}
