import Foundation
import GMCCDaemonKit

/// CLARIFY_FINALIZE — answering → complete; writes refined goal/detail and copies refined_goal into prompt.goal.
enum ClarifyFinalizeHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyFinalizeRequest.self, from: line)
        return try okResult(.clarifyFinalize, head, try store.clarifyFinalize(request))
    }
}
