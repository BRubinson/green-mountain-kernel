import Foundation

/// DOPE_INGEST — files → db, whole-tree overwrite gated on exactly revision + 1.
///
/// Every child uuid changes (uuid-free JSON, no smart diff).
enum DopeIngestHandler {
    /// Handles a dope ingest request and writes the tree to the database.
    /// - Parameters:
    ///   - line: The request payload.
    ///   - head: The envelope metadata.
    ///   - store: The data store.
    /// - Returns: The handler result with the ingest response.
    /// - Throws: `StoreError` on validation or persistence failure.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeIngestRequest.self, from: line)
        return try okResult(.dopeIngest, head, try store.dopeIngest(request))
    }
}
