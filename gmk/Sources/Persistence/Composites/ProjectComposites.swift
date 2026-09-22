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

    /// The same shape joined to the parent instance. `session` carries no
    /// `project_uuid`, so project scope rides this join, and the caller
    /// constrains the instance further through the alias it passes in — the
    /// join has to be applied before `asRequest(of:)` rebinds the decoder.
    static func request(
        instance: TableAlias<InstanceRecord>,
        projectUuid: String?
    ) -> QueryInterfaceRequest<Self> {
        let request =
            SessionRecord
            .annotated(with: SqlAnnotations.lastActivityAt)
            .joining(required: SessionRecord.instance.aliased(instance))
            .asRequest(of: Self.self)
        guard let projectUuid else { return request }
        return request.filter(instance[InstanceRecord.Columns.projectUuid] == projectUuid)
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

/// One session's lineage keys, gathered across the two tiers above it.
///
/// The branch a promotion is allowed from is configured on the project, so the
/// predicate needs the session's code, its project and that project's primary
/// branch together; each is annotated under the key its property carries.
struct SessionLineage: FetchableRecord, Decodable {
    var sessionCode: String
    var projectUuid: String
    var primaryBranch: String

    static func request(sessionUuid: String) -> QueryInterfaceRequest<Self> {
        let instance = TableAlias<InstanceRecord>()
        let project = TableAlias<ProjectRecord>()
        return
            SessionRecord
            .all()
            .withUuid(sessionUuid)
            .joining(
                required: SessionRecord.instance
                    .aliased(instance)
                    .joining(required: InstanceRecord.project.aliased(project))
            )
            .select(
                SessionRecord.Columns.code.forKey("sessionCode"),
                instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid"),
                project[ProjectRecord.Columns.primaryProjectBranch].forKey("primaryBranch")
            )
            .asRequest(of: Self.self)
    }
}

/// The prompt row the listing surfaces, ordered the way its scope reads.
///
/// `prompt` names no column and no scope, so GRDB decodes it from the base
/// row through `PromptRecord.init(row:)`. The report enrichment PROMPT_LIST
/// can attach is not part of this shape: it is four grouped aggregations over
/// other tables, folded in by the caller, never a per-row subquery.
struct PromptSummary: FetchableRecord, Decodable {
    var prompt: PromptRecord

    /// A nil `sessionUuid` reads every prompt in the db, where `seq` is unique
    /// only inside one session and so orders under its parent.
    static func request(sessionUuid: String?) -> QueryInterfaceRequest<Self> {
        guard let sessionUuid else {
            return
                PromptRecord
                .order(PromptRecord.Columns.sessionUuid, PromptRecord.Columns.seq)
                .asRequest(of: Self.self)
        }
        return
            PromptRecord
            .filter(PromptRecord.Columns.sessionUuid == sessionUuid)
            .orderedBySeq()
            .asRequest(of: Self.self)
    }
}
