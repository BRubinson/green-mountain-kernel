import Foundation
import GMCCDaemonKit

/// DOPE_GET — full-tree read; PROMPT scope preferred, SESSION_INSTANCE fallback.
enum DopeGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeGetRequest.self, from: line)
        return try okResult(.dopeGet, head, try store.dopeGet(request))
    }
}
