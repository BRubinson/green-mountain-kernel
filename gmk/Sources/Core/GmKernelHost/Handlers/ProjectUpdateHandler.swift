import Foundation

/// PROJECT_UPDATE — set the project's primary_project_branch.
enum ProjectUpdateHandler {
    /// Handles a project update request.
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The envelope metadata.
    ///   - store: The data store.
    /// - Returns: The handler result with the updated project.
    /// - Throws: `StoreError` on validation or persistence failure.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(ProjectUpdateRequest.self, from: line)
        return try okResult(
            .projectUpdate,
            head,
            ProjectResponse(project: try store.updateProject(req))
        )
    }
}
