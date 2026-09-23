import Foundation

/// REVIEW_RESOLVE — record one finding's resolution; UNGATED on summary status (the fix loop runs after complete).
enum ReviewResolveHandler {
    /// Handles a review resolve request to record a finding's resolution.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the resolution response.
    /// - Throws: Any error from decoding the request or recording the resolution.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewResolveRequest.self, from: line)
        return try okResult(.reviewResolve, head, try store.reviewResolve(request))
    }
}
