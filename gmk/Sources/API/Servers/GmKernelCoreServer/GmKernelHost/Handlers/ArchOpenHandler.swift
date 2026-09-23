import Foundation

/// ARCH_OPEN — idempotent create-or-return of the architecture summary.
///
/// Never transitions the prompt.
enum ArchOpenHandler {
    /// Handles ARCH_OPEN request to create or return the architecture summary.
    ///
    /// Idempotent; never transitions the prompt.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The store instance.
    /// - Returns: A handler result with the architecture summary response.
    /// - Throws: Any decoding or store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchOpenRequest.self, from: line)
        return try okResult(.archOpen, head, try store.archOpen(request))
    }
}
