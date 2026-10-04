import Foundation

/// DOPE_PROMOTE — publish a session's SESSION_INSTANCE tree into the
/// project's BASE_PROJECT scope.
enum DopePromoteHandler {
    /// Handles a dope promote request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header containing prompt uuid and other routing info.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the operation outcome.
    /// - Throws: Errors from decoding or store operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopePromoteRequest.self, from: line)
        return try okResult(.dopePromote, head, try store.dopePromote(req))
    }
}
