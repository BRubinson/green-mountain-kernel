import Foundation
import GMCCDaemonKit

/// EXPLORE_COMPLETE — exploring → complete; refuses unranked findings; the ONLY write path for overview.
enum ExploreCompleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreCompleteRequest.self, from: line)
        return try okResult(.exploreComplete, head, try store.exploreComplete(request))
    }
}
