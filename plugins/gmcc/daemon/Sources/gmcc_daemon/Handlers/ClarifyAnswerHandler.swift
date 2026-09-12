import Foundation
import GMCCDaemonKit

/// CLARIFY_ANSWER — answer or skip one clarification row (summary must be answering); pure row update.
enum ClarifyAnswerHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyAnswerRequest.self, from: line)
        return try okResult(.clarifyAnswer, head, try store.clarifyAnswer(request))
    }
}
