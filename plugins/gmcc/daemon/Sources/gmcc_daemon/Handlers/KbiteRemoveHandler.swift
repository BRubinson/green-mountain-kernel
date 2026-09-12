import Foundation
import GMCCDaemonKit

/// KBITE_REMOVE — drop a kbite from one scope's registry. Db only.
enum KbiteRemoveHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteRemoveRequest.self, from: line)
        return try okResult(.kbiteRemove, head, try store.removeKbite(request))
    }
}
