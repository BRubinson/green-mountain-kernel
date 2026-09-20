import Foundation
import GmDaemon
import GmDaemonSdk

/// CLARIFY_OPEN — idempotent create-or-return of the clarification summary.
/// Never transitions the prompt: status has a single front door elsewhere.
enum ClarifyOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyOpenRequest.self, from: line)
        return try okResult(.clarifyOpen, head, try store.clarifyOpen(request))
    }
}
