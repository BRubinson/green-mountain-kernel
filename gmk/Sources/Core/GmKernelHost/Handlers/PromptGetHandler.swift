import Foundation

/// PROMPT_GET — full prompt row + artifact pointers + kbite codes + change
/// summary.
///
/// Backs bot resume logic's branch-on-status.
enum PromptGetHandler {
    /// Handle a PROMPT_GET request.
    /// - Parameters:
    ///   - line: The encoded request data.
    ///   - head: The envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with prompt data.
    /// - Throws: Decoding, storage, or retrieval errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptGetRequest.self, from: line)
        return try okResult(.promptGet, head, try store.getPrompt(request))
    }
}
