import Foundation
import GMCCDaemonKit

/// CONTEXT_ENSURE — upsert project → instance → session from repo identity,
/// seeding kbite inheritance down the chain at create time (mirrors
/// gmcc_session_startup.sh's lazy creation + inherit_kbite). Idempotent.
enum ContextEnsureHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ContextEnsureRequest.self, from: line)
        return try okResult(.contextEnsure, head, try store.ensureContext(request))
    }
}
