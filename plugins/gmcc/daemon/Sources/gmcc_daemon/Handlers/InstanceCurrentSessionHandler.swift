import Foundation
import GMCCDaemonKit

/// INSTANCE_CURRENT_SESSION — the session matching the instance's checked-out branch, or none.
enum InstanceCurrentSessionHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(InstanceCurrentSessionRequest.self, from: line)
        return try okResult(.instanceCurrentSession, head, try store.instanceCurrentSession(request))
    }
}
