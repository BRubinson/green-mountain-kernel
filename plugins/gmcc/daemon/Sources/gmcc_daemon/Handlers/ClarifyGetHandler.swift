import Foundation
import GMCCDaemonKit

/// CLARIFY_GET — summary plus ordered clarification rows for a prompt.
enum ClarifyGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifyGetRequest.self, from: line)
        return try okResult(.clarifyGet, head, try store.clarifyGet(request))
    }
}
