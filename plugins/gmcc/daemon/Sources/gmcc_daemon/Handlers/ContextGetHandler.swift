import Foundation
import GMCCDaemonKit

/// CONTEXT_GET — read-only resolution of the current gmcc environment.
/// Never creates rows.
enum ContextGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ContextGetRequest.self, from: line)
        return try okResult(.contextGet, head, try store.getContext(request))
    }
}
