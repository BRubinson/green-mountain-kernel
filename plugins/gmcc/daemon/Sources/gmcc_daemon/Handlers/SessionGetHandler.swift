import Foundation
import GMCCDaemonKit

/// SESSION_GET — one-shot session context: session row + prompt stubs +
/// change summaries (per-prompt entries stay empty until file changes carry
/// prompt attribution).
enum SessionGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionGetRequest.self, from: line)
        return try okResult(.sessionGet, head, try store.getSession(request))
    }
}
