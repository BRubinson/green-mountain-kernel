import Foundation
import GMCCDaemonKit

/// REVIEW_COMPLETE — reviewing → complete; refuses unranked findings; the ONLY write path for overview + verdict.
enum ReviewCompleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewCompleteRequest.self, from: line)
        return try okResult(.reviewComplete, head, try store.reviewComplete(request))
    }
}
