import Foundation

/// PROJECT_LIST — enumerate all projects (read-only).
enum ProjectListHandler {
    /// Handles a project list request.
    /// - Parameters:
    ///   - line: The encoded request payload (unused for this read-only request).
    ///   - head: The envelope header for this request.
    ///   - store: The store instance to query.
    /// - Returns: The handler result with the list of projects.
    /// - Throws: `HandlerError` or `StoreError` if the request fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(ProjectListRequest.self, from: line)
        return try okResult(.projectList, head, try store.listProjects())
    }
}
