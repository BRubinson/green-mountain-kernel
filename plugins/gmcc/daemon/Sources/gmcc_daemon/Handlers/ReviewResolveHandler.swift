import Foundation
import GMCCDaemonKit

/// REVIEW_RESOLVE — record one finding's resolution; UNGATED on summary status (the fix loop runs after complete).
enum ReviewResolveHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewResolveRequest.self, from: line)
        return try okResult(.reviewResolve, head, try store.reviewResolve(request))
    }
}
