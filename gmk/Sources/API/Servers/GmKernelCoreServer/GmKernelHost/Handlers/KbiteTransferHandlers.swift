import Foundation

// KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE — the portable-kbite family.
// The wire carries paths and counts only; zip assembly and source-tree
// moves are the gm CLI's job.

enum KbiteExportHandler {
    /// Handles the KBITE_EXPORT wire request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the export response.
    /// - Throws: Errors from decoding or export operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteExportRequest.self, from: line)
        return try okResult(.kbiteExport, head, try store.exportKbite(request))
    }
}

enum KbiteImportHandler {
    /// Handles the KBITE_IMPORT wire request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the import response.
    /// - Throws: Errors from decoding or import operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteImportRequest.self, from: line)
        return try okResult(.kbiteImport, head, try store.importKbite(request))
    }
}

enum KbiteDeleteHandler {
    /// Handles the KBITE_DELETE wire request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the delete response.
    /// - Throws: Errors from decoding or delete operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteDeleteRequest.self, from: line)
        return try okResult(.kbiteDelete, head, try store.deleteKbite(request))
    }
}
