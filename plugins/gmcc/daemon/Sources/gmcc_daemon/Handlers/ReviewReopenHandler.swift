import Foundation
import GMCCDaemonKit

/// REVIEW_REOPEN — complete → reviewing revision edge; preserves all data (verdict survives until re-complete).
enum ReviewReopenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewReopenRequest.self, from: line)
        return try okResult(.reviewReopen, head, try store.reviewReopen(request))
    }
}
