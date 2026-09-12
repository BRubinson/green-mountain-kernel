import Foundation
import GMCCDaemonKit

/// ARCH_PROPOSE — drafting → proposed; change rows sealed for review.
enum ArchProposeHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchProposeRequest.self, from: line)
        return try okResult(.archPropose, head, try store.archPropose(request))
    }
}
