import Foundation
import GMCCDaemonKit

/// SESSION_LIST — enumerate sessions, optionally filtered to one instance
/// (read-only; unknown instance uuid ⇒ NOT_FOUND).
enum SessionListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionListRequest.self, from: line)
        return try okResult(.sessionList, head, try store.listSessions(request))
    }
}
