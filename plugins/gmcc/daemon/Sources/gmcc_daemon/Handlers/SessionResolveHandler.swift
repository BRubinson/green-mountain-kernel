import Foundation
import GMCCDaemonKit

/// SESSION_RESOLVE — session row + git-derived checked-out state (.git/HEAD read, no subprocess).
enum SessionResolveHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionResolveRequest.self, from: line)
        return try okResult(.sessionResolve, head, try store.sessionResolve(request))
    }
}
