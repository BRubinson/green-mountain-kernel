import Foundation

/// CLARIFY_SEAL — building → answering; locks the question list.
enum ClarifySealHandler {
    /// Handles a clarify seal request.
    ///
    /// - Parameters:
    ///   - line: The wire data containing the seal request.
    ///   - head: The envelope metadata.
    ///   - store: The store to perform the seal operation on.
    /// - Returns: The handler result with the seal response.
    /// - Throws: Errors if decoding or the seal operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifySealRequest.self, from: line)
        return try okResult(.clarifySeal, head, try store.clarifySeal(request))
    }
}
