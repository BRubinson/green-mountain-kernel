import Foundation
import GmDaemon
import GmDaemonSdk

/// EXPLORE_REOPEN — complete → exploring revision edge; preserves all data.
enum ExploreReopenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreReopenRequest.self, from: line)
        return try okResult(.exploreReopen, head, try store.exploreReopen(request))
    }
}
