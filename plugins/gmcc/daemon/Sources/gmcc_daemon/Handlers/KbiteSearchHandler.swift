import Foundation
import GMCCDaemonKit

/// KBITE_SEARCH — FTS5 ranked stubs, optionally scoped by kbite_uuids.
enum KbiteSearchHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteSearchRequest.self, from: line)
        return try okResult(.kbiteSearch, head, try store.searchKbites(request))
    }
}
