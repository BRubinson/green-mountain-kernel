import Foundation
import GMCCDaemonKit

/// KBITE_ADD — explicit-only registration at one scope. Db only — no yaml
/// write-through (the interim yaml sync is the client skill's job).
enum KbiteAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteAddRequest.self, from: line)
        return try okResult(.kbiteAdd, head, try store.addKbite(request))
    }
}
