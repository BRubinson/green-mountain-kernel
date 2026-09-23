import Foundation

/// KBITE_DIGEST — one-step chewed → db import; deletes the temporary chewed
/// files after commit, keeps raw sources on disk.
enum KbiteDigestHandler {
    /// Handles a kbite digest request.
    ///
    /// - Parameters:
    ///   - line: The encoded request data.
    ///   - head: The envelope header containing request metadata.
    ///   - store: The storage layer for kbite access.
    /// - Returns: The handler result with the digest response.
    /// - Throws: Any error from decoding or digesting the kbite.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteDigestRequest.self, from: line)
        return try okResult(.kbiteDigest, head, try store.digestKbite(request))
    }
}
