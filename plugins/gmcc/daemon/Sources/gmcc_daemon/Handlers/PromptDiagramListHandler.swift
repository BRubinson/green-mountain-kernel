import Foundation
import GMCCDaemonKit

/// PROMPT_DIAGRAM_LIST — every diagram this prompt has qualified, so a
/// resuming session sees what it already understood without re-reading images.
enum PromptDiagramListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptDiagramListRequest.self, from: line)
        return try okResult(.promptDiagramList, head, try store.promptDiagramList(request))
    }
}
