import Foundation
import GMCCDaemonKit

/// DOPE_INIT — idempotent create-or-return of a dope scope (scope_type
/// derived from the presence of prompt_uuid; optional clone-from-base fork).
enum DopeInitHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeInitRequest.self, from: line)
        return try okResult(.dopeInit, head, try store.dopeInit(request))
    }
}
