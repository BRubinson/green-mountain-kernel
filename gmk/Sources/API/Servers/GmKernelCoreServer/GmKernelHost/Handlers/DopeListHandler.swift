import Foundation

/// DOPE_LIST — scope enumeration for pickers (SESSION_INSTANCE, or one prompt's
/// PROMPT scopes; unknown uuid ⇒ NOT_FOUND, no scopes ⇒ empty list).
enum DopeListHandler {
    /// Handles a dope list request.
    ///
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The request envelope header.
    ///   - store: The persistent store.
    /// - Returns: The handler result with the dope list response.
    /// - Throws: Error if the request fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeListRequest.self, from: line)
        return try okResult(.dopeList, head, try store.dopeList(request))
    }
}
