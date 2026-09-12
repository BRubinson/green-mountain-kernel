import Foundation
import GMCCDaemonKit

/// INSTANCE_LIST — enumerate instances, optionally filtered to one project
/// (read-only; unknown project uuid ⇒ NOT_FOUND).
enum InstanceListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(InstanceListRequest.self, from: line)
        return try okResult(.instanceList, head, try store.listInstances(request))
    }
}
