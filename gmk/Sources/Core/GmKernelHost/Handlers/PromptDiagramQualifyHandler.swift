import Foundation

/// PROMPT_DIAGRAM_QUALIFY — record what this prompt makes of a rendered
/// diagram.
///
/// Upserts on (prompt, diagram): the newest reading stands.
enum PromptDiagramQualifyHandler {
    /// Handle a PROMPT_DIAGRAM_QUALIFY request.
    ///
    /// - Parameters:
    ///   - line: The payload data.
    ///   - head: The envelope head.
    ///   - store: The kernel store.
    /// - Returns: The handler result.
    /// - Throws: Any request or database error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptDiagramQualifyRequest.self, from: line)
        return try okResult(.promptDiagramQualify, head, try store.promptDiagramQualify(request))
    }
}
