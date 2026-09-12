import Foundation
import GMCCDaemonKit

/// KBITE_DIGEST — one-step chewed → db import; deletes the temporary chewed
/// files after commit, keeps raw sources on disk.
enum KbiteDigestHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteDigestRequest.self, from: line)
        return try okResult(.kbiteDigest, head, try store.digestKbite(request))
    }
}
