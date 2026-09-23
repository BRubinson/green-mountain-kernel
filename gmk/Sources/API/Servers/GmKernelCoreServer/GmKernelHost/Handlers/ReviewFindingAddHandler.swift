import Foundation

/// REVIEW_FINDING_ADD — insert a finding (optional file/line location; rating optional).
enum ReviewFindingAddHandler {
    /// Handles a review finding add request.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header containing prompt uuid and other routing info.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the operation outcome.
    /// - Throws: Errors from decoding or store operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewFindingAddRequest.self, from: line)
        return try okResult(.reviewFindingAdd, head, try store.reviewFindingAdd(request))
    }
}
