import Foundation
import GMCCDaemonKit

/// DOPE_NODE_DELETE — level-parameterized guarded delete with ordered
/// RESTRICT-safe cascades and referrer pre-checks. Scope deletion refused.
enum DopeNodeDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeDeleteRequest.self, from: line)
        return try okResult(.dopeNodeDelete, head, try store.dopeNodeDelete(request))
    }
}
