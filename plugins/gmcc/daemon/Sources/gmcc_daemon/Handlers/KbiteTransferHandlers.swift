import Foundation
import GMCCDaemonKit

// KBITE_EXPORT / KBITE_IMPORT / KBITE_DELETE — the portable-kbite family.
// The wire carries paths and counts only; zip assembly and source-tree
// moves are the gm CLI's job.

enum KbiteExportHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteExportRequest.self, from: line)
        return try okResult(.kbiteExport, head, try store.exportKbite(request))
    }
}

enum KbiteImportHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteImportRequest.self, from: line)
        return try okResult(.kbiteImport, head, try store.importKbite(request))
    }
}

enum KbiteDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(KbiteDeleteRequest.self, from: line)
        return try okResult(.kbiteDelete, head, try store.deleteKbite(request))
    }
}
