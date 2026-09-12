import Foundation
import GMCCDaemonKit

/// DOPE_LIST — scope enumeration for pickers (SESSION_INSTANCE, or one prompt's
/// PROMPT scopes; unknown uuid ⇒ NOT_FOUND, no scopes ⇒ empty list).
enum DopeListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeListRequest.self, from: line)
        return try okResult(.dopeList, head, try store.dopeList(request))
    }
}
