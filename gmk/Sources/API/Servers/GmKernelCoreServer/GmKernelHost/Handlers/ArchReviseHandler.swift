import Foundation

/// ARCH_REVISE — proposed → drafting, the revision edge.
enum ArchReviseHandler {
    /// Handles an architecture revision request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header with metadata.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the revised architecture.
    /// - Throws: Server errors during processing or persistence.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchReviseRequest.self, from: line)
        return try okResult(.archRevise, head, try store.archRevise(request))
    }
}
