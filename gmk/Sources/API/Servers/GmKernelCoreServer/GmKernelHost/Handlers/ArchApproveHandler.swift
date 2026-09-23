import Foundation

/// ARCH_APPROVE — proposed → approved (terminal); unlocks architecting → implementing.
enum ArchApproveHandler {
    /// Handles an architecture approve request.
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header for the request.
    ///   - store: The persistence store for the operation.
    /// - Returns: A handler result with the approval response.
    /// - Throws: Any error from decoding the request or approving the architecture.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchApproveRequest.self, from: line)
        return try okResult(.archApprove, head, try store.archApprove(request))
    }
}
