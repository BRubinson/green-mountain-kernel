import Foundation
import GMCCDaemonKit

/// EXPLORE_KEY_FILE_ADD — add one key file to the shared deduped set (duplicate path = idempotent upsert-ignore).
enum ExploreKeyFileAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreKeyFileAddRequest.self, from: line)
        return try okResult(.exploreKeyFileAdd, head, try store.exploreKeyFileAdd(request))
    }
}
