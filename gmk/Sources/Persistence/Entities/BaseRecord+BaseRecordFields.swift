// Shared read-only surface for records carrying the BaseEntity columns.
//
// A table's decode type is its record, declared with TableRecord and
// SnakeCaseDecoded in that table's entity file alongside its associations.
// Records are FetchableRecord only: no PersistableRecord, and no deleteAll,
// deleteOne or updateAll, which the no_record_bulk_write lint rule enforces.
// Every write routes through StoreCore so the version gate stays single-sourced.
// `db` never enters Entities/, so records stay flat and decodable from a row.

import Foundation
import GRDB

/// Opt-in snake_case column mapping.
///
/// Every read-side decoder declares this conformance explicitly — there is NO
/// blanket `extension FetchableRecord where Self: Codable` here, so a query
/// struct added inside a repository cannot silently inherit a decoding strategy
/// from a file nobody opened. A scope read through `including(optional:)` or
/// `including(required:)` inherits the PARENT's strategy, so every joined child
/// declares this itself.
protocol SnakeCaseDecoded: Codable, FetchableRecord {
    // no requirements: conformance IS the opt-in
}

extension SnakeCaseDecoded {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}

/// A record mirroring a live table, carrying the BaseEntity columns.
///
/// Note there is no `id` (SQLite rowid) property: the daemon's identity is
/// `uuid` everywhere, records are FetchableRecord-only so a rowid can never be
/// used for a write, and a non-optional `id` would make every Record unable to
/// decode the explicit-column-list SELECTs that omit it. `DaemonEventRecord`
/// is the sole exception — there the rowid IS the wire identity
/// (`EventNotification.id`, the SUBSCRIBE replay cursor).
protocol BaseRecordFields: SnakeCaseDecoded, Sendable {
    static var databaseTableName: String { get }
    var uuid: String { get }
    var version: Int64 { get }
}

/// The by-uuid lookups every record shares, over the query interface rather
/// than a hand-written SELECT. Constrained rather than folded into
/// `BaseRecordFields` itself: the protocol stays free of TableRecord, so a
/// projection decoder can adopt it without claiming to mirror a table.
extension BaseRecordFields where Self: TableRecord {
    /// Fetches the record with the given uuid.
    /// - Parameters:
    ///   - db: The database to query.
    ///   - uuid: The unique identifier to look up.
    /// - Returns: The record, or nil if not found.
    /// - Throws: Any database error.
    static func fetch(_ db: Database, uuid: String) throws -> Self? {
        try Self.all().withUuid(uuid).fetchOne(db)
    }

    /// Fetches the record with the given uuid or throws.
    /// - Parameters:
    ///   - db: The database to query.
    ///   - uuid: The unique identifier to look up.
    /// - Returns: The record.
    /// - Throws: `StoreError.notFound` if the record does not exist.
    static func require(_ db: Database, uuid: String) throws -> Self {
        guard let row = try fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: databaseTableName, key: uuid)
        }
        return row
    }
}
