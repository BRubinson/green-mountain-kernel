import Foundation
import GMCCDaemonKit

/// PROMPT_SET_STATUS — validated forward-only lifecycle transition
/// draft → clarifying → clarified; emits PROMPT_STATUS_CHANGE.
enum PromptSetStatusHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptSetStatusRequest.self, from: line)
        return try okResult(.promptSetStatus, head, try store.setPromptStatus(request))
    }
}
