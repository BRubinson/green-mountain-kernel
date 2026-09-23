import Foundation

/// PROMPT_LIST — lightweight stubs (seq, code, status, uuid) for a session.
enum PromptListHandler {
    /// Handles a PROMPT_LIST request and returns lightweight prompt stubs.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store for data access.
    /// - Returns: The handler result with the list response.
    /// - Throws: Decoding or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptListRequest.self, from: line)
        return try okResult(.promptList, head, try store.listPrompts(request))
    }
}
