import Foundation
import GMCCDaemonKit

/// PROMPT_CREATE — atomically allocates the next per-session seq (replaces
/// the max-id+1 yaml scan), inserts the prompt row with seeded
/// prompt_active_kbite links. Db only — no yaml write-through.
enum PromptCreateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptCreateRequest.self, from: line)
        return try okResult(.promptCreate, head, try store.createPrompt(request))
    }
}
