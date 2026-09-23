import Foundation

/// EXPLORE_OPEN — idempotent create-or-return of the exploration summary.
///
/// EXPLICIT-only: exploration runs while the prompt is still draft, so no
/// status transition may call it.
enum ExploreOpenHandler {
    /// Handles EXPLORE_OPEN request to create or return the exploration summary.
    ///
    /// Idempotent; EXPLICIT-only since exploration runs while the prompt is
    /// still draft, so no status transition may call it.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The store instance.
    /// - Returns: A handler result with the exploration summary response.
    /// - Throws: Any decoding or store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreOpenRequest.self, from: line)
        return try okResult(.exploreOpen, head, try store.exploreOpen(request))
    }
}
