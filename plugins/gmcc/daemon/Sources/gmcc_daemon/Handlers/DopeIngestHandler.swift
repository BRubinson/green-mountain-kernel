import Foundation
import GMCCDaemonKit

/// DOPE_INGEST — files → db, whole-tree overwrite gated on exactly
/// revision + 1. Every child uuid changes (uuid-free JSON, no smart diff).
enum DopeIngestHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeIngestRequest.self, from: line)
        return try okResult(.dopeIngest, head, try store.dopeIngest(request))
    }
}
