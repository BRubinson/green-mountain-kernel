import Foundation

/// DOPE_NODE_UPDATE — level-parameterized guarded update (expected-version).
enum DopeNodeUpdateHandler {
    /// Handles a DOPE_NODE_UPDATE request to update a dope node with version guard.
    ///
    /// - Parameters:
    ///   - line: The wire request data.
    ///   - head: The envelope header.
    ///   - store: The kernel store for persistence.
    /// - Returns: The handler result with the response.
    /// - Throws: Decoding or persistence errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeUpdateRequest.self, from: line)
        return try okResult(.dopeNodeUpdate, head, try store.dopeNodeUpdate(request))
    }
}
