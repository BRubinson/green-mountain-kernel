import Foundation

/// PROMPT_DIAGRAM_LIST — every diagram this prompt has qualified, so a
/// resuming session sees what it already understood without re-reading images.
enum PromptDiagramListHandler {
    /// Handles the PROMPT_DIAGRAM_LIST request.
    ///
    /// Returns every diagram this prompt has qualified, so a resuming session
    /// sees what it already understood without re-reading images.
    ///
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the diagram list response.
    /// - Throws: `StoreError` for database failures; decoding errors on malformed requests.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptDiagramListRequest.self, from: line)
        return try okResult(.promptDiagramList, head, try store.promptDiagramList(request))
    }
}
