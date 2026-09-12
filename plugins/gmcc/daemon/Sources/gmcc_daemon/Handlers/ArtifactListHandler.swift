import Foundation
import GMCCDaemonKit

/// ARTIFACT_LIST — artifact pointers for a prompt, so resume/review flows
/// know which phase files exist without globbing.
enum ArtifactListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArtifactListRequest.self, from: line)
        return try okResult(.artifactList, head, try store.listArtifacts(request))
    }
}
