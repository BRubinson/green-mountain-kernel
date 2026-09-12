import Foundation
import GMCCDaemonKit

/// KBITE_GET — one kbite with resources, file stubs (no content), keywords.
enum KbiteGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteGetRequest.self, from: line)
        return try okResult(.kbiteGet, head, try store.getKbite(request))
    }
}
