import Foundation
import GMCCDaemonKit

/// CLARIFY_SEAL — building → answering; locks the question list.
enum ClarifySealHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ClarifySealRequest.self, from: line)
        return try okResult(.clarifySeal, head, try store.clarifySeal(request))
    }
}
