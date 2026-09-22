// Composite read shapes over the identity-spine tables.
//
// A composite is a decode target for one request: its properties are Records,
// arrays of Records, or annotated scalars, and it owns the request that fills
// it. Wire mapping lives in Mapping/, never here.

import Foundation
import GRDB

/// A session row carried with its recency annotation.
///
/// `session` names no column and no scope, so GRDB decodes it from the base
/// row through `SessionRecord.init(row:)`, which applies that record's own
/// snake_case strategy. `lastActivityAt` decodes from the annotation's alias.
struct SessionSummary: FetchableRecord, Decodable {
    var session: SessionRecord
    var lastActivityAt: String

    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord.annotated(with: SqlAnnotations.lastActivityAt).asRequest(of: Self.self)
    }
}

/// A session row carried with its activation registry.
///
/// `session` names no column and no scope, so GRDB decodes it from the base
/// row through `SessionRecord.init(row:)`. The prefetch always yields an
/// array, empty when the session holds no claim.
struct SessionWithActivations: FetchableRecord, Decodable {
    var session: SessionRecord
    var activations: [PromptActivationRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        SessionRecord
            .including(all: SessionRecord.activations.orderedByCreatedAt())
            .asRequest(of: Self.self)
    }
}
