import Foundation
import GMCCDaemonKit

/// DOPE_PROMOTE — publish a session's SESSION_INSTANCE tree into the
/// project's BASE_PROJECT scope.
enum DopePromoteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopePromoteRequest.self, from: line)
        return try okResult(.dopePromote, head, try store.dopePromote(req))
    }
}
