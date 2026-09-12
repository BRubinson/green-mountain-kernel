import Foundation
import GMCCDaemonKit

/// DOPE_SEARCH — full-text over the dope tree at prompt/session/project scope.
enum DopeSearchHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeSearchRequest.self, from: line)
        return try okResult(.dopeSearch, head, try store.dopeSearch(req))
    }
}
