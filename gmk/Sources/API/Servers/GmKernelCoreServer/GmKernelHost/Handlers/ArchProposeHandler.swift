import Foundation

/// ARCH_PROPOSE — drafting → proposed; change rows sealed for review.
enum ArchProposeHandler {
    /// Handles an architecture proposal request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the proposal response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchProposeRequest.self, from: line)
        return try okResult(.archPropose, head, try store.archPropose(request))
    }
}
