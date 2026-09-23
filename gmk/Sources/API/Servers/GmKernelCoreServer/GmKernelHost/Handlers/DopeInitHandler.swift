import Foundation

/// DOPE_INIT — idempotent create-or-return of a dope scope (scope_type
/// derived from the presence of prompt_uuid; optional clone-from-base fork).
enum DopeInitHandler {
    /// Handles a DOPE_INIT verb request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope head with verb and session info.
    ///   - store: The store to execute the request against.
    /// - Returns: The handler result with the response.
    /// - Throws: Validation or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeInitRequest.self, from: line)
        return try okResult(.dopeInit, head, try store.dopeInit(request))
    }
}
