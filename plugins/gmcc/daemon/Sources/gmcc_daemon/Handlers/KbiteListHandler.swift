import Foundation
import GMCCDaemonKit

/// KBITE_LIST — registry at a scope, resolved through the inheritance chain
/// at read time.
enum KbiteListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteListRequest.self, from: line)
        return try okResult(.kbiteList, head, try store.listKbites(request))
    }
}
