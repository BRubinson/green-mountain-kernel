import Foundation

/// PROMPT_UPDATE_CONTENT — Draft-only edit of the STAY TRUE triple
/// (backstory/goal/detail); CONTENT_LOCKED once Clarifying/Clarified.
///
/// This is the GMVibes editor write path.
enum PromptUpdateContentHandler {
    /// Handles a prompt content update request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header with request metadata.
    ///   - store: The persistence store to apply the update.
    /// - Returns: The handler result with status and response.
    /// - Throws: A handler error if the update fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptUpdateContentRequest.self, from: line)
        return try okResult(.promptUpdateContent, head, try store.updatePromptContent(request))
    }
}
