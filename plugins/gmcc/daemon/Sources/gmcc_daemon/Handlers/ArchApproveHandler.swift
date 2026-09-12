import Foundation
import GMCCDaemonKit

/// ARCH_APPROVE — proposed → approved (terminal); unlocks architecting → implementing.
enum ArchApproveHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchApproveRequest.self, from: line)
        return try okResult(.archApprove, head, try store.archApprove(request))
    }
}
