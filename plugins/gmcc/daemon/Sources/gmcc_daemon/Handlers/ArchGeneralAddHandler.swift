import Foundation
import GMCCDaemonKit

/// ARCH_GENERAL_ADD — add a general change row (drafting only; path normalized; change_code capped).
enum ArchGeneralAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchGeneralAddRequest.self, from: line)
        return try okResult(.archGeneralAdd, head, try store.archGeneralAdd(request))
    }
}
