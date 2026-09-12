import Foundation
import GMCCDaemonKit

/// DOPE_NODE_UPDATE — level-parameterized guarded update (expected-version).
enum DopeNodeUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeUpdateRequest.self, from: line)
        return try okResult(.dopeNodeUpdate, head, try store.dopeNodeUpdate(request))
    }
}
