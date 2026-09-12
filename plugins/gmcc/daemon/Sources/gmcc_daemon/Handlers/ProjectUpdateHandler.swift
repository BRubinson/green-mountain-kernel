import Foundation
import GMCCDaemonKit

/// PROJECT_UPDATE — set the project's primary_project_branch.
enum ProjectUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(ProjectUpdateRequest.self, from: line)
        return try okResult(.projectUpdate, head,
                            ProjectResponse(project: try store.updateProject(req)))
    }
}
