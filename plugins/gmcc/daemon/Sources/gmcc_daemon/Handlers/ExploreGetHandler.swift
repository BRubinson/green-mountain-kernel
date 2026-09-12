import Foundation
import GMCCDaemonKit

/// EXPLORE_GET — threshold-partitioned read (full rows under the rating window plus every unranked row; stubs outside).
enum ExploreGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreGetRequest.self, from: line)
        return try okResult(.exploreGet, head, try store.exploreGet(request))
    }
}
