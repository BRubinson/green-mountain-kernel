import Foundation
import GMCCDaemonKit

/// PROJECT_LIST — enumerate all projects (read-only).
enum ProjectListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(ProjectListRequest.self, from: line)
        return try okResult(.projectList, head, try store.listProjects())
    }
}
