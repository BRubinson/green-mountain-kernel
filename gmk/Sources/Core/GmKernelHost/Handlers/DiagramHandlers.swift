import Foundation

// DIAGRAM_* (v15) — thin decode+dispatch shims, one per verb. The NODE
// verbs land in the store as one-mutation batches over the same body as
// DIAGRAM_BATCH_APPLY, so granular and batch semantics cannot drift.

/// DIAGRAM_INIT — create-or-return, idempotent per (tier owner, code).
enum DiagramInitHandler {
    /// Handles a diagram initialization request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the diagram initialization response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramInitRequest.self, from: line)
        return try okResult(.diagramInit, head, try store.diagramInit(request))
    }
}

/// DIAGRAM_LIST — one owner, one tier, never a union (the v12 contract).
enum DiagramListHandler {
    /// Handles a diagram listing request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the diagram listing response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramListRequest.self, from: line)
        return try okResult(.diagramList, head, try store.diagramList(request))
    }
}

/// DIAGRAM_GET — full tree + read-time dope binding resolutions.
enum DiagramGetHandler {
    /// Handles a diagram retrieval request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the diagram tree and bindings.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramGetRequest.self, from: line)
        return try okResult(.diagramGet, head, try store.diagramGet(request))
    }
}

/// DIAGRAM_NODE_ADD — one-mutation batch.
enum DiagramNodeAddHandler {
    /// Handles a diagram node addition request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the mutation response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeAddRequest.self, from: line)
        return try okResult(.diagramNodeAdd, head, try store.diagramNodeAdd(request))
    }
}

/// DIAGRAM_NODE_UPDATE — one-mutation batch.
enum DiagramNodeUpdateHandler {
    /// Handles a diagram node update request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the mutation response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeUpdateRequest.self, from: line)
        return try okResult(.diagramNodeUpdate, head, try store.diagramNodeUpdate(request))
    }
}

/// DIAGRAM_NODE_DELETE — one-mutation batch (subtree CASCADE).
enum DiagramNodeDeleteHandler {
    /// Handles a diagram node deletion request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the mutation response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramNodeDeleteRequest.self, from: line)
        return try okResult(.diagramNodeDelete, head, try store.diagramNodeDelete(request))
    }
}

/// DIAGRAM_BATCH_APPLY — THE interactive write: one transaction, one
/// revision bump, one DIAGRAM_CHANGE event.
enum DiagramBatchApplyHandler {
    /// Handles a diagram batch apply request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the batch response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramBatchApplyRequest.self, from: line)
        return try okResult(.diagramBatchApply, head, try store.diagramBatchApply(request))
    }
}

// Diagram Studio (v23)

enum DiagramSearchHandler {
    /// Handles a diagram search request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the search response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramSearchRequest.self, from: line)
        return try okResult(.diagramSearch, head, try store.diagramSearch(request))
    }
}

enum DiagramDeleteHandler {
    /// Handles a diagram deletion request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the deletion response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramDeleteRequest.self, from: line)
        return try okResult(.diagramDelete, head, try store.diagramDelete(request))
    }
}

enum DiagramWriteRepoHandler {
    /// Handles a diagram repository write request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the write response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramWriteRepoRequest.self, from: line)
        return try okResult(.diagramWriteRepo, head, try store.diagramWriteRepo(request))
    }
}

enum DiagramIngestHandler {
    /// Handles a diagram ingest request.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: The handler result with the ingest response.
    /// - Throws: Errors from request decoding or store operation.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DiagramIngestRequest.self, from: line)
        return try okResult(.diagramIngest, head, try store.diagramIngest(request))
    }
}
