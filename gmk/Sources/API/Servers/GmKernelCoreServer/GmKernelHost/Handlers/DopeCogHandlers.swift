import Foundation

/// The COGS verb family.
///
/// One handler per message, each the ten-line shape DopeListHandler established.
enum DopeCogAddHandler {
    /// Handles a dopeCogAdd request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogAddRequest.self, from: line)
        return try okResult(.dopeCogAdd, head, try store.dopeCogAdd(req))
    }
}

enum DopeCogUpdateHandler {
    /// Handles a dopeCogUpdate request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogUpdateRequest.self, from: line)
        return try okResult(.dopeCogUpdate, head, try store.dopeCogUpdate(req))
    }
}

enum DopeCogDeleteHandler {
    /// Handles a dopeCogDelete request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogDeleteRequest.self, from: line)
        return try okResult(.dopeCogDelete, head, try store.dopeCogDelete(req))
    }
}

enum DopeCogGetHandler {
    /// Handles a dopeCogGet request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogGetRequest.self, from: line)
        return try okResult(.dopeCogGet, head, try store.dopeCogGet(req))
    }
}

enum DopeCogElementAddHandler {
    /// Handles a dopeCogElementAdd request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementAddRequest.self, from: line)
        return try okResult(.dopeCogElementAdd, head, try store.dopeCogElementAdd(req))
    }
}

enum DopeCogElementUpdateHandler {
    /// Handles a dopeCogElementUpdate request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementUpdateRequest.self, from: line)
        return try okResult(.dopeCogElementUpdate, head, try store.dopeCogElementUpdate(req))
    }
}

enum DopeCogElementDeleteHandler {
    /// Handles a dopeCogElementDelete request.
    ///
    /// - Parameters:
    ///   - line: The message payload.
    ///   - head: The message envelope header.
    ///   - store: The data store.
    /// - Returns: A handler result containing the response.
    /// - Throws: An error if decoding or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementDeleteRequest.self, from: line)
        return try okResult(.dopeCogElementDelete, head, try store.dopeCogElementDelete(req))
    }
}
