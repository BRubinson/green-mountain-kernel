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

/// Opt-in snake_case column mapping. Every read-side decoder in this module
/// declares this conformance explicitly — there is deliberately NO blanket
/// `extension FetchableRecord where Self: Codable` here, so a query struct
/// added inside a repository cannot silently inherit a decoding strategy from
/// a file nobody opened.
///
/// A scope read through `including(optional:)` or `including(required:)`
/// inherits the PARENT's strategy, so every joined child declares this itself.
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

extension BaseRecordFields {
    static func fetch(_ db: Database, uuid: String) throws -> Self? {
        try fetchOne(db, sql: "SELECT * FROM \(databaseTableName) WHERE uuid = ?", arguments: [uuid])
    }

    static func require(_ db: Database, uuid: String) throws -> Self {
        guard let row = try fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: databaseTableName, key: uuid)
        }
        return row
    }

    /// Single-row twin of `fetchAll(where:)`, for a lookup keyed by something
    /// other than uuid (`fetch(_:uuid:)` covers that case).
    static func fetchOne(
        _ db: Database,
        where condition: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> Self? {
        try fetchOne(
            db,
            sql: "SELECT * FROM \(databaseTableName) WHERE \(condition)",
            arguments: arguments
        )
    }

    /// `SELECT * FROM <table> [WHERE …] [ORDER BY …]`, so a converted fetch
    /// does not re-type the table name the protocol already owns.
    ///
    /// NOT for `kbite_resource_file`: its stub reads deliberately project
    /// `resource_file_content IS NOT NULL AS has_content` to keep ~115 MB of
    /// content out of the result set. Use KbiteResourceFileStubRecord.
    static func fetchAll(
        _ db: Database,
        where condition: String? = nil,
        arguments: StatementArguments = StatementArguments(),
        orderBy: String? = nil
    ) throws -> [Self] {
        var sql = "SELECT * FROM \(databaseTableName)"
        if let condition { sql += " WHERE \(condition)" }
        if let orderBy { sql += " ORDER BY \(orderBy)" }
        return try fetchAll(db, sql: sql, arguments: arguments)
    }
}
