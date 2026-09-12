import Foundation
import GMCCDaemonKit

/// REVIEW_GET — threshold-partitioned read (stubs carry status so the fix loop sees resolution state).
enum ReviewGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewGetRequest.self, from: line)
        return try okResult(.reviewGet, head, try store.reviewGet(request))
    }
}
