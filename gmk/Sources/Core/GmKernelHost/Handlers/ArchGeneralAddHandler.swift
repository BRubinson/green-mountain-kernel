import Foundation

/// ARCH_GENERAL_ADD — add a general change row (drafting only; path normalized; change_code capped).
enum ArchGeneralAddHandler {
    /// Processes an ARCH_GENERAL_ADD request and returns the result.
    /// - Parameters:
    ///   - line: The raw request data.
    ///   - head: The message envelope.
    ///   - store: The database store.
    /// - Returns: The handler result with the added row.
    /// - Throws: Decoding or store errors if the request is invalid.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchGeneralAddRequest.self, from: line)
        return try okResult(.archGeneralAdd, head, try store.archGeneralAdd(request))
    }
}
