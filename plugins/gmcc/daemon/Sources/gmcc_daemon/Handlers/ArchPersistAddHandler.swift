import Foundation
import GMCCDaemonKit

/// ARCH_PERSIST_ADD — add a persistence-layer change row (drafting only; path normalized).
enum ArchPersistAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchPersistAddRequest.self, from: line)
        return try okResult(.archPersistAdd, head, try store.archPersistAdd(request))
    }
}
