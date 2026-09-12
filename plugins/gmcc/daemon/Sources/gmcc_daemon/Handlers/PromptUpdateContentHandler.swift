import Foundation
import GMCCDaemonKit

/// PROMPT_UPDATE_CONTENT — Draft-only edit of the STAY TRUE triple
/// (backstory/goal/detail); CONTENT_LOCKED once Clarifying/Clarified.
/// This is the GMVibes editor write path.
enum PromptUpdateContentHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptUpdateContentRequest.self, from: line)
        return try okResult(.promptUpdateContent, head, try store.updatePromptContent(request))
    }
}
