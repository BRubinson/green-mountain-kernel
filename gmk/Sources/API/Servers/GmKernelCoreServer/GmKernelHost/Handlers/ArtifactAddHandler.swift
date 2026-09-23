import Foundation

/// ARTIFACT_ADD — register a file pointer for a bot-phase memory/ file
/// (kind explore|architecture|review|qualified|other).
///
/// Content stays in the file; re-registering the same path updates kind/note.
enum ArtifactAddHandler {
    /// Handles an ARTIFACT_ADD verb request from the wire.
    ///
    /// - Parameters:
    ///   - line: The verb line payload data.
    ///   - head: The envelope header containing request metadata.
    ///   - store: The store instance to add the artifact to.
    /// - Returns: A handler result with the artifact add response.
    /// - Throws: `HandlerError` errors if decoding or add fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArtifactAddRequest.self, from: line)
        return try okResult(.artifactAdd, head, try store.addArtifact(request))
    }
}
