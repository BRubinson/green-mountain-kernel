import Foundation
import GMCCDaemonKit

/// ARCH_REVISE — proposed → drafting, the revision edge.
enum ArchReviseHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchReviseRequest.self, from: line)
        return try okResult(.archRevise, head, try store.archRevise(request))
    }
}
