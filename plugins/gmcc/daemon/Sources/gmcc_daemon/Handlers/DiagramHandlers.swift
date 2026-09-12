import Foundation
import GMCCDaemonKit

// DIAGRAM_* (v15) — thin decode+dispatch shims, one per verb. The NODE
// verbs land in the store as one-mutation batches over the same body as
// DIAGRAM_BATCH_APPLY, so granular and batch semantics cannot drift.

/// DIAGRAM_INIT — create-or-return, idempotent per (tier owner, code).
enum DiagramInitHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramInitRequest.self, from: line)
        return try okResult(.diagramInit, head, try store.diagramInit(request))
    }
}

/// DIAGRAM_LIST — one owner, one tier, never a union (the v12 contract).
enum DiagramListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramListRequest.self, from: line)
        return try okResult(.diagramList, head, try store.diagramList(request))
    }
}

/// DIAGRAM_GET — full tree + read-time dope binding resolutions.
enum DiagramGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramGetRequest.self, from: line)
        return try okResult(.diagramGet, head, try store.diagramGet(request))
    }
}

/// DIAGRAM_NODE_ADD — one-mutation batch.
enum DiagramNodeAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeAddRequest.self, from: line)
        return try okResult(.diagramNodeAdd, head, try store.diagramNodeAdd(request))
    }
}

/// DIAGRAM_NODE_UPDATE — one-mutation batch.
enum DiagramNodeUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeUpdateRequest.self, from: line)
        return try okResult(.diagramNodeUpdate, head, try store.diagramNodeUpdate(request))
    }
}

/// DIAGRAM_NODE_DELETE — one-mutation batch (subtree CASCADE).
enum DiagramNodeDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeDeleteRequest.self, from: line)
        return try okResult(.diagramNodeDelete, head, try store.diagramNodeDelete(request))
    }
}

/// DIAGRAM_BATCH_APPLY — THE interactive write: one transaction, one
/// revision bump, one DIAGRAM_CHANGE event.
enum DiagramBatchApplyHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramBatchApplyRequest.self, from: line)
        return try okResult(.diagramBatchApply, head, try store.diagramBatchApply(request))
    }
}

// Diagram Studio (v23)

enum DiagramSearchHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramSearchRequest.self, from: line)
        return try okResult(.diagramSearch, head, try store.diagramSearch(request))
    }
}

enum DiagramDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramDeleteRequest.self, from: line)
        return try okResult(.diagramDelete, head, try store.diagramDelete(request))
    }
}

enum DiagramWriteRepoHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramWriteRepoRequest.self, from: line)
        return try okResult(.diagramWriteRepo, head, try store.diagramWriteRepo(request))
    }
}

enum DiagramIngestHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramIngestRequest.self, from: line)
        return try okResult(.diagramIngest, head, try store.diagramIngest(request))
    }
}
