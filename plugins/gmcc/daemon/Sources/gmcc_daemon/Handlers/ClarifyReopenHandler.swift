import Foundation
import GMCCDaemonKit

/// CLARIFY_REOPEN — complete → answering, the revision edge.
enum ClarifyReopenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyReopenRequest.self, from: line)
        return try okResult(.clarifyReopen, head, try store.clarifyReopen(request))
    }
}
