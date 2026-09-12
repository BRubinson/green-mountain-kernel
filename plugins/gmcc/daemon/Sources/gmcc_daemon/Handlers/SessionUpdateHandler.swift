import Foundation
import GMCCDaemonKit

/// SESSION_UPDATE — optimistic-concurrency guarded partial update of
/// session-owned scalars (name, backstory, goal, status active|closed).
enum SessionUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionUpdateRequest.self, from: line)
        return try okResult(.sessionUpdate, head, try store.updateSession(request))
    }
}
