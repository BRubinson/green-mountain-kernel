import Foundation

/// KBITE_FILE_GET — a single resource file including full content (the
/// targeted load replacing "cat the chewed file").
enum KbiteFileGetHandler {
    /// Handles a kbite file fetch request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The kernel store.
    /// - Returns: The handler result.
    /// - Throws: `HandlerError` on request failure.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteFileGetRequest.self, from: line)
        return try okResult(.kbiteFileGet, head, try store.getKbiteFile(request))
    }
}
