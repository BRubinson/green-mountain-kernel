import Foundation
import GMCCDaemonKit

/// ARCH_FIELD_ADD — add a field-level row under a persistence change (drafting only).
enum ArchFieldAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchFieldAddRequest.self, from: line)
        return try okResult(.archFieldAdd, head, try store.archFieldAdd(request))
    }
}
