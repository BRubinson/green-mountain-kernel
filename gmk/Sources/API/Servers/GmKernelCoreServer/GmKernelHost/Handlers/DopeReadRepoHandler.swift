import Foundation

/// DOPE_READ_REPO — parse + validate {instance_root}/.gmcc; never writes.
///
/// Filesystem access runs OUTSIDE any db lock (see Store+DopeRepo).
enum DopeReadRepoHandler {
    /// Handles DOPE_READ_REPO command to parse and validate the dope repository.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: A handler result with the dope repository response.
    /// - Throws: Errors from payload decoding or repository access.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeReadRepoRequest.self, from: line)
        return try okResult(.dopeReadRepo, head, try store.dopeReadRepo(request))
    }
}
