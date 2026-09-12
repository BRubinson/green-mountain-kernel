import Foundation
import GMCCDaemonKit

/// PROMPT_DIAGRAM_QUALIFY — record what this prompt makes of a rendered
/// diagram. Upserts on (prompt, diagram): the newest reading stands.
enum PromptDiagramQualifyHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptDiagramQualifyRequest.self, from: line)
        return try okResult(.promptDiagramQualify, head, try store.promptDiagramQualify(request))
    }
}
