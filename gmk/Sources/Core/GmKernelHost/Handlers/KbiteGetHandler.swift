import Foundation

/// KBITE_GET — one kbite with resources, file stubs (no content), keywords.
enum KbiteGetHandler {
    /// Handles a KBITE_GET request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The request envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result with the kbite response.
    /// - Throws: Any error from decoding or processing the request.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteGetRequest.self, from: line)
        return try okResult(.kbiteGet, head, try store.getKbite(request))
    }
}
