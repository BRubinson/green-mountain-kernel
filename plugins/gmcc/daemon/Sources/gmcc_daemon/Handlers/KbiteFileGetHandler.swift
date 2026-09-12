import Foundation
import GMCCDaemonKit

/// KBITE_FILE_GET — a single resource file including full content (the
/// targeted load replacing "cat the chewed file").
enum KbiteFileGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteFileGetRequest.self, from: line)
        return try okResult(.kbiteFileGet, head, try store.getKbiteFile(request))
    }
}
