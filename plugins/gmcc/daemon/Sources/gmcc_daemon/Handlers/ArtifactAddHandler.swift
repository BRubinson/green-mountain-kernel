import Foundation
import GMCCDaemonKit

/// ARTIFACT_ADD — register a file pointer for a bot-phase memory/ file
/// (kind explore|architecture|review|qualified|other). Content stays in the
/// file; re-registering the same path updates kind/note.
enum ArtifactAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArtifactAddRequest.self, from: line)
        return try okResult(.artifactAdd, head, try store.addArtifact(request))
    }
}
