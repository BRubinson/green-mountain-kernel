import Foundation
import GMCCDaemonKit

/// DOPE_NODE_ADD — level-parameterized child insert (the DopeLevelSpec
/// registry maps level → table/parent/legal fields).
enum DopeNodeAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeAddRequest.self, from: line)
        return try okResult(.dopeNodeAdd, head, try store.dopeNodeAdd(request))
    }
}
