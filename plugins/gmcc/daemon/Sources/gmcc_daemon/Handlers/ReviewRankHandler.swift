import Foundation
import GMCCDaemonKit

/// REVIEW_RANK — atomic version-less batch rank (same contract as EXPLORE_RANK).
enum ReviewRankHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewRankRequest.self, from: line)
        return try okResult(.reviewRank, head, try store.reviewRank(request))
    }
}
