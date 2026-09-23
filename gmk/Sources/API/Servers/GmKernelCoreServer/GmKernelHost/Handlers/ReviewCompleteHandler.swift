import Foundation

/// REVIEW_COMPLETE — reviewing → complete; refuses unranked findings; the ONLY write path for overview + verdict.
enum ReviewCompleteHandler {
    /// Handles a REVIEW_COMPLETE request to finish code review with ranked findings.
    ///
    /// The only write path for overview and verdict. Refuses unranked findings.
    ///
    /// - Parameters:
    ///   - line: The wire request data.
    ///   - head: The envelope header.
    ///   - store: The kernel store for persistence.
    /// - Returns: The handler result with the response.
    /// - Throws: Decoding or persistence errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ReviewCompleteRequest.self, from: line)
        return try okResult(.reviewComplete, head, try store.reviewComplete(request))
    }
}
