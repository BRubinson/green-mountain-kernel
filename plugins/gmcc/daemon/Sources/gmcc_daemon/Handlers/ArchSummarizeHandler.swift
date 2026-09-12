import Foundation
import GMCCDaemonKit

/// ARCH_SUMMARIZE — set the concept-level body (drafting only).
enum ArchSummarizeHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchSummarizeRequest.self, from: line)
        return try okResult(.archSummarize, head, try store.archSummarize(request))
    }
}
