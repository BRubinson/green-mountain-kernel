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
    func orderedBySeq() -> Self {
        order(Column("seq"))
    }
}

extension DerivableRequest where RowDecoder: SoftDeletable {
    /// Keeps only the rows whose `deleted_on` is NULL.
    func notDeleted() -> Self {
        filter(Column("deleted_on") == nil)
    }

    /// Applies `notDeleted()` only when the caller asks for it.
    func notDeleted(_ apply: Bool) -> Self {
        apply ? notDeleted() : self
    }

    /// Names at the call site the deliberate choice to read deleted rows too.
    func includingDeleted() -> Self {
        self
    }
}

extension DerivableRequest where RowDecoder: Rankable {
    /// Keeps only the rows whose `finding_rating` is NULL.
    func unranked() -> Self {
        filter(Column("finding_rating") == nil)
    }
}

extension DerivableRequest where RowDecoder: ParentKeyed {
    /// Keeps only the rows belonging to the parent with this uuid.
    func forParent(_ uuid: String) -> Self {
        filter(RowDecoder.parentColumn == uuid)
    }
}

extension DerivableRequest where RowDecoder: BaseRecordFields {
    /// Keeps only the row carrying this uuid.
    func withUuid(_ uuid: String) -> Self {
        filter(Column("uuid") == uuid)
    }

    /// Orders the rows by `created_at`, ascending.
    func orderedByCreatedAt() -> Self {
        order(Column("created_at"))
    }
}

/// Selections that carry SQL no association can express.
enum SqlAnnotations {
    /// A session's recency: the latest of its own `updated_at`, its prompts'
    /// `updated_at` and its file changes' `created_at`. The timestamps are
    /// ISO-8601 seconds-Z strings, so MAX over them is chronological, and a
    /// childless session still sorts by its own recency.
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

/// The highest `seq` among one parent's children, or 0 when it has none.
/// A caller placing a new row adds 1 inside its own write transaction.
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
