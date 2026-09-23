// Shared request builders for the Persistence module.
//
// Four marker protocols name a column family a table carries. The
// DerivableRequest extensions below turn each marker into a named filter or
// ordering, so a predicate is spelled once here and referred to by name at
// every read site.

import Foundation
import GRDB

/// A table carrying a `seq` column that orders its rows inside one parent.
protocol SeqOrdered: TableRecord {}

/// A table carrying a `deleted_on` column, where NULL means the row is alive.
protocol SoftDeletable: TableRecord {}

/// A table carrying a `finding_rating` column, where NULL means unranked.
protocol Rankable: TableRecord {}

/// A table whose rows each belong to one parent row.
protocol ParentKeyed: TableRecord {
    /// The column holding the parent row's uuid.
    static var parentColumn: Column { get }
}

extension DerivableRequest where RowDecoder: SeqOrdered {
    /// Orders the rows by `seq`, ascending.
    /// - Returns: A request with rows ordered by sequence number.
    func orderedBySeq() -> Self {
        order(Column("seq"))
    }
}

extension DerivableRequest where RowDecoder: SoftDeletable {
    /// Keeps only the rows whose `deleted_on` is NULL.
    /// - Returns: A request filtered to include only non-deleted rows.
    func notDeleted() -> Self {
        filter(Column("deleted_on") == nil)
    }

    /// Applies `notDeleted()` only when the caller asks for it.
    /// - Parameter apply: Whether to filter out deleted rows; when false, the request is unchanged.
    /// - Returns: A filtered request if `apply` is true; otherwise the original request.
    func notDeleted(_ apply: Bool) -> Self {
        apply ? notDeleted() : self
    }

    /// Names at the call site the deliberate choice to read deleted rows too.
    /// - Returns: The request unchanged, with deleted rows included.
    func includingDeleted() -> Self {
        self
    }
}

extension DerivableRequest where RowDecoder: Rankable {
    /// Keeps only the rows whose `finding_rating` is NULL.
    /// - Returns: A request filtered to include only unranked rows.
    func unranked() -> Self {
        filter(Column("finding_rating") == nil)
    }
}

extension DerivableRequest where RowDecoder: ParentKeyed {
    /// Keeps only the rows belonging to the parent with this uuid.
    /// - Parameter uuid: The parent row's UUID.
    /// - Returns: A request filtered to include only rows with the given parent.
    func forParent(_ uuid: String) -> Self {
        filter(RowDecoder.parentColumn == uuid)
    }
}

extension DerivableRequest {
    /// Keeps only the row the request's own table carries this uuid on.
    ///
    /// Unconstrained by RowDecoder so it survives `asRequest(of:)`: a composite
    /// decodes to a struct that is no Record, and the filter belongs to the
    /// base table either way.
    /// - Parameter uuid: The row's UUID.
    /// - Returns: A request filtered to include only the row with the given UUID.
    func withUuid(_ uuid: String) -> Self {
        filter(Column("uuid") == uuid)
    }
}

extension DerivableRequest where RowDecoder: BaseRecordFields {
    /// Orders the rows by `created_at`, ascending.
    /// - Returns: A request with rows ordered by creation time.
    func orderedByCreatedAt() -> Self {
        order(Column("created_at"))
    }
}

extension DerivableRequest {
    /// Keeps only the rows whose own `prompt_uuid` belongs to this session.
    ///
    /// A nil session reads every prompt's rows, the way the unscoped listing does.
    ///
    /// The column is spelled as a string because four summary tables carry it,
    /// so no one `Columns` case names it for every request this reaches.
    /// - Parameter sessionUuid: The session's UUID, or nil to include all prompts.
    /// - Returns: A request filtered to include only rows from prompts in the session.
    func forSessionPrompts(_ sessionUuid: String?) -> Self {
        guard let sessionUuid else { return self }
        return filter(
            PromptRecord
                .select(PromptRecord.Columns.uuid)
                .filter(PromptRecord.Columns.sessionUuid == sessionUuid)
                .contains(Column("prompt_uuid"))
        )
    }
}

/// Request builders over the kbite tables that decode something other than a
/// composite, so they belong to the request vocabulary rather than Composites.
enum KbiteRequests {
    /// The shared-vocabulary keywords tagged on one resource file.
    ///
    /// The junction is the root because the file side of the read is already
    /// in hand: only the words are missing.
    /// - Parameter fileUuid: The UUID of the resource file.
    /// - Returns: A request that decodes to the keyword strings for the file.
    static func fileKeywords(fileUuid: String) -> QueryInterfaceRequest<String> {
        let keyword = TableAlias<KeywordRecord>()
        return
            ResourceFileKeywordJunctionRecord
            .filter(ResourceFileKeywordJunctionRecord.Columns.fileUuid == fileUuid)
            .joining(required: ResourceFileKeywordJunctionRecord.keyword.aliased(keyword))
            .order(keyword[KeywordRecord.Columns.keyword])
            .select(keyword[KeywordRecord.Columns.keyword], as: String.self)
    }
}

/// Selections that carry SQL no association can express.
enum SqlAnnotations {
    /// A session's recency: the latest of its own `updated_at`, its prompts'
    /// `updated_at` and its file changes' `created_at`.
    ///
    /// The timestamps are ISO-8601 seconds-Z strings, so MAX over them is chronological, and a childless session still
    /// sorts by its own recency.
    static let lastActivityAt: SQLSelection = SQL(
        sql: """
            MAX(
                session.updated_at,
                COALESCE((SELECT MAX(p.updated_at) FROM prompt p
                          WHERE p.session_uuid = session.uuid), ''),
                COALESCE((SELECT MAX(fc.created_at) FROM file_change fc
                          WHERE fc.session_uuid = session.uuid), '')
            )
            """
    )
    .forKey("lastActivityAt")
}

/// Finds the highest sequence number among one parent's children.
///
/// A caller placing a new row adds 1 inside its own write transaction.
/// - Parameters:
///   - db: The database to query.
///   - type: The record type to query.
///   - parent: The column holding the parent UUID on the table.
///   - uuid: The parent row's UUID.
/// - Returns: The highest `seq` value among the parent's children, or 0 if it has none.
/// - Throws: Any error from the database during the read.
func nextSeq<T: TableRecord>(
    _ db: Database,
    in type: T.Type,
    parent: Column,
    uuid: String
) throws -> Int64 {
    try type.filter(parent == uuid)
        .select(max(Column("seq")) ?? 0, as: Int64.self)
        .fetchOne(db) ?? 0
}
