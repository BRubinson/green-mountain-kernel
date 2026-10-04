import Foundation

/// DOPE_NODE_DELETE — level-parameterized guarded delete with ordered
/// RESTRICT-safe cascades and referrer pre-checks.
///
/// Scope deletion refused.
enum DopeNodeDeleteHandler {
    /// Handle a DOPE_NODE_DELETE request.
    /// - Parameters:
    ///   - line: The encoded request data.
    ///   - head: The envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result.
    /// - Throws: Decoding, storage, or deletion errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeDeleteRequest.self, from: line)
        return try okResult(.dopeNodeDelete, head, try store.dopeNodeDelete(request))
    }
}
