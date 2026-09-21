import Foundation

/// EXPLORE_OPEN — idempotent create-or-return of the exploration summary.
/// EXPLICIT-only: exploration runs while the prompt is still draft, so no
/// status transition may call it.
enum ExploreOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreOpenRequest.self, from: line)
        return try okResult(.exploreOpen, head, try store.exploreOpen(request))
    }
}
