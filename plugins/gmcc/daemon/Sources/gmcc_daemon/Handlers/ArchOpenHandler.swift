import Foundation
import GMCCDaemonKit

/// ARCH_OPEN — idempotent create-or-return of the architecture summary. Never transitions the prompt.
enum ArchOpenHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchOpenRequest.self, from: line)
        return try okResult(.archOpen, head, try store.archOpen(request))
    }
}
