import Foundation
import GMCCDaemonKit

/// KBITE_KEYWORD_TAG — attach/detach normalized keywords at kbite or
/// resource-file level.
enum KbiteKeywordTagHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteKeywordTagRequest.self, from: line)
        return try okResult(.kbiteKeywordTag, head, try store.tagKeyword(request))
    }
}
