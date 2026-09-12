import Foundation
import GMCCDaemonKit

/// REVIEW_FINDING_ADD — insert a finding (optional file/line location; rating optional).
enum ReviewFindingAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewFindingAddRequest.self, from: line)
        return try okResult(.reviewFindingAdd, head, try store.reviewFindingAdd(request))
    }
}
