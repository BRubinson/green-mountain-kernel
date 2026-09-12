import Foundation
import GMCCDaemonKit

/// PROMPT_GET — full prompt row + artifact pointers + kbite codes + change
/// summary. Backs bot resume logic's branch-on-status.
enum PromptGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptGetRequest.self, from: line)
        return try okResult(.promptGet, head, try store.getPrompt(request))
    }
}
