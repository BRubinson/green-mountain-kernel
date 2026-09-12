import Foundation
import GMCCDaemonKit

/// PROMPT_LIST — lightweight stubs (seq, code, status, uuid) for a session.
enum PromptListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptListRequest.self, from: line)
        return try okResult(.promptList, head, try store.listPrompts(request))
    }
}
