import Foundation
import GMCCDaemonKit

/// EXPLORE_RANK — atomic version-less batch rank (whole batch validates before any write).
enum ExploreRankHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreRankRequest.self, from: line)
        return try okResult(.exploreRank, head, try store.exploreRank(request))
    }
}
