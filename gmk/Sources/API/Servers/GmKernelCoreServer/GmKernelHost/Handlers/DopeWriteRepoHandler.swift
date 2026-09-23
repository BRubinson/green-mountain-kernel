import Foundation

/// DOPE_WRITE_REPO — db → files via the sandbox's staged atomic swap;
/// refuses when the files are ahead of the db unless forced.
enum DopeWriteRepoHandler {
    /// Handles a DOPE_WRITE_REPO request to write the dope repo to disk.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header with request metadata.
    ///   - store: The store to execute the write operation.
    /// - Returns: The handler result with response data.
    /// - Throws: Any error during request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeWriteRepoRequest.self, from: line)
        return try okResult(.dopeWriteRepo, head, try store.dopeWriteRepo(request))
    }
}
