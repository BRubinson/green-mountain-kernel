import Foundation

/// INSTANCE_LIST — enumerate instances, optionally filtered to one project
/// (read-only; unknown project uuid ⇒ NOT_FOUND).
enum InstanceListHandler {
    /// Handles an instance list request, returning instances optionally filtered to a project.
    ///
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The message envelope header.
    ///   - store: The database store.
    /// - Returns: The result containing the instance list.
    /// - Throws: `StoreError.notFound` if the project UUID is unknown, or any other store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(InstanceListRequest.self, from: line)
        return try okResult(.instanceList, head, try store.listInstances(request))
    }
}
