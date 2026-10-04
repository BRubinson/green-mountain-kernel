import Foundation

/// ARTIFACT_LIST — artifact pointers for a prompt, so resume/review flows
/// know which phase files exist without globbing.
enum ArtifactListHandler {
    /// Handles an artifact list request, returning artifact pointers for a prompt.
    ///
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The message envelope header.
    ///   - store: The database store.
    /// - Returns: The result containing artifact list data.
    /// - Throws: Any error from store queries or decoding.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArtifactListRequest.self, from: line)
        return try okResult(.artifactList, head, try store.listArtifacts(request))
    }
}
