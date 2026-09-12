import Foundation
import GMCCDaemonKit

/// PROMPT_DIAGRAM_GET — one qualification, by (prompt, diagram) or by a
/// prompt that has exactly one. A real prompt with none answers
/// SUMMARY_ABSENT, never NOT_FOUND.
enum PromptDiagramGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptDiagramGetRequest.self, from: line)
        return try okResult(.promptDiagramGet, head, try store.promptDiagramGet(request))
    }
}
