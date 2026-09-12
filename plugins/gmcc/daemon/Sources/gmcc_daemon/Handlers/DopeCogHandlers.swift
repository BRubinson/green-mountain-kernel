import Foundation
import GMCCDaemonKit

/// The COGS verb family. One handler per message, each the ten-line shape
/// DopeListHandler established.
enum DopeCogAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogAddRequest.self, from: line)
        return try okResult(.dopeCogAdd, head, try store.dopeCogAdd(req))
    }
}

enum DopeCogUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogUpdateRequest.self, from: line)
        return try okResult(.dopeCogUpdate, head, try store.dopeCogUpdate(req))
    }
}

enum DopeCogDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogDeleteRequest.self, from: line)
        return try okResult(.dopeCogDelete, head, try store.dopeCogDelete(req))
    }
}

enum DopeCogGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogGetRequest.self, from: line)
        return try okResult(.dopeCogGet, head, try store.dopeCogGet(req))
    }
}

enum DopeCogElementAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementAddRequest.self, from: line)
        return try okResult(.dopeCogElementAdd, head, try store.dopeCogElementAdd(req))
    }
}

enum DopeCogElementUpdateHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementUpdateRequest.self, from: line)
        return try okResult(.dopeCogElementUpdate, head, try store.dopeCogElementUpdate(req))
    }
}

enum DopeCogElementDeleteHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let req = try decodePayload(DopeCogElementDeleteRequest.self, from: line)
        return try okResult(.dopeCogElementDelete, head, try store.dopeCogElementDelete(req))
    }
}
