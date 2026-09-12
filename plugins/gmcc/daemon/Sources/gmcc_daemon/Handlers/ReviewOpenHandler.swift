import Foundation
import GMCCDaemonKit

/// REVIEW_OPEN — idempotent create-or-return of the review summary. EXPLICIT-only: prompt status transitions never create or gate on it (skip-to-done stays legal).
enum ReviewOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewOpenRequest.self, from: line)
        return try okResult(.reviewOpen, head, try store.reviewOpen(request))
    }
}
