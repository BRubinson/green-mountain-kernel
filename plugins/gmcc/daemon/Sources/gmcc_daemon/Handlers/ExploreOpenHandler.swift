import Foundation
import GMCCDaemonKit

/// EXPLORE_OPEN — idempotent create-or-return of the exploration summary. EXPLICIT-only: never called from prompt status transitions (exploration runs while the prompt is still draft).
enum ExploreOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreOpenRequest.self, from: line)
        return try okResult(.exploreOpen, head, try store.exploreOpen(request))
    }
}
