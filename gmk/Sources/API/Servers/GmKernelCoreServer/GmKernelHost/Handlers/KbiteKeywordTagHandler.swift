import Foundation

/// KBITE_KEYWORD_TAG — attach/detach normalized keywords at kbite or
/// resource-file level.
enum KbiteKeywordTagHandler {
    /// Handles a KBITE_KEYWORD_TAG request to attach or detach keywords.
    ///
    /// - Parameters:
    ///   - line: The serialized request payload.
    ///   - head: The envelope header with request metadata.
    ///   - store: The data store to update.
    /// - Returns: The handler result with the tagging response.
    /// - Throws: `EnvelopeError` or `StoreError` on decoding or data access failures.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteKeywordTagRequest.self, from: line)
        return try okResult(.kbiteKeywordTag, head, try store.tagKeyword(request))
    }
}
