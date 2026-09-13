import Foundation
import GmDaemon
import GmDaemonSdk

/// PROMPT_SET_STATUS — validated lifecycle transition over the three-state
/// prompt lifecycle (draft → initiated → done, and done → draft to re-open);
/// emits PROMPT_STATUS_CHANGE.
enum PromptSetStatusHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptSetStatusRequest.self, from: line)
        return try okResult(.promptSetStatus, head, try store.setPromptStatus(request))
    }
}
