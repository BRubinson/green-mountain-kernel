import Foundation
import GMCCDaemonKit

/// CLARIFY_OPEN — idempotent create-or-return of the clarification summary. Never transitions the prompt (single-front-door rule); on a legacy prompt this is the explicit adoption path.
enum ClarifyOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyOpenRequest.self, from: line)
        return try okResult(.clarifyOpen, head, try store.clarifyOpen(request))
    }
}
