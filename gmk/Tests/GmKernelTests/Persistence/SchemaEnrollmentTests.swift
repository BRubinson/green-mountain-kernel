import Foundation
import GRDB
import XCTest

/// The drift net over the enrolled persistence surface.
///
/// Every assertion reads the LIVE schema of the booted kernel through the
/// shared read-only handle, so what passes here passes against the database the
/// daemon actually migrated, not against a hand-kept copy of it.
final class SchemaEnrollmentTests: KernelBackedTestCase {

    /// One mirror record per table, and every one of them decodes a full row.
    ///
    /// The row is fabricated from `columns(in:)`, so a column the schema gained
    /// or lost shows up as a decode failure naming its table. A record whose
    /// `databaseTableName` has drifted fails earlier, at `columns(in:)`.
    func testEveryRecordMatchesItsTable() throws {
        let mirrors = SchemaEnrollment.records.filter { $0.kind == .mirror }
        XCTAssertEqual(mirrors.count, 71, "a table mirror left the roster or never joined it")

        try env.readOnlyDatabase()
            .read { db in
                for entry in mirrors {
                    let columns = try db.columns(in: entry.table)
                    XCTAssertFalse(columns.isEmpty, entry.table)
                    XCTAssertNoThrow(try entry.decode(Self.fabricatedRow(for: columns)), entry.table)
                }
            }
    }

    /// Every association's foreign key resolves to exactly one candidate.
    ///
    /// GRDB traps rather than throwing when inference finds none or several, so
    /// this reads the `foreign_key_list` pragma and never prepares a request.
    func testEveryAssociationResolvesItsForeignKey() throws {
        XCTAssertEqual(SchemaEnrollment.associations.count, 150, "an association left the roster or never joined it")

        try env.readOnlyDatabase()
            .read { db in
                for entry in SchemaEnrollment.associations {
                    let keys = try Self.foreignKeys(for: entry, in: db)
                    if let originColumns = entry.originColumns {
                        XCTAssertTrue(keys.contains { $0.originColumns == originColumns }, entry.label)
                    } else {
                        XCTAssertEqual(keys.count, 1, entry.label)
                    }
                }
            }
    }

    /// Every association whose key resolved also compiles to SQL.
    ///
    /// An association that failed the pragma check is skipped: preparing it is
    /// the trap the previous test exists to keep unreached.
    func testEveryAssociationRequestCompiles() throws {
        try env.readOnlyDatabase()
            .read { db in
                for entry in SchemaEnrollment.associations {
                    guard try Self.resolves(entry, in: db) else { continue }
                    let sql = try entry.prepare(db)
                    XCTAssertFalse(sql.isEmpty, entry.label)
                    XCTAssertTrue(sql.contains(entry.destination) || entry.isPrefetch, entry.label)
                }
            }
    }

    /// Every composite's canonical request compiles against the live schema.
    func testEveryCompositeRequestCompiles() throws {
        XCTAssertEqual(SchemaEnrollment.composites.count, 4, "a composite left the roster or never joined it")

        try env.readOnlyDatabase()
            .read { db in
                for entry in SchemaEnrollment.composites {
                    let sql = try entry.prepare(db)
                    XCTAssertFalse(sql.isEmpty, entry.label)
                }
            }
    }

    // MARK: - Fabrication

    /// A row carrying one value per column, typed by declared affinity.
    private static func fabricatedRow(for columns: [ColumnInfo]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [:]
        for column in columns {
            values[column.name] = dummy(forDeclaredType: column.type)
        }
        return Row(values)
    }

    /// SQLite affinity is a prefix rule; BLOB and an undeclared type land on `Data`.
    private static func dummy(forDeclaredType declaredType: String) -> any DatabaseValueConvertible {
        let type = declaredType.uppercased()
        if type.hasPrefix("INT") { return Int64(1) }
        if type.hasPrefix("TEXT") || type.hasPrefix("CHAR") || type.hasPrefix("CLOB") { return "1" }
        if type.hasPrefix("REAL") || type.hasPrefix("FLOA") || type.hasPrefix("DOUB") { return 1.0 }
        return Data()
    }

    // MARK: - Foreign keys

    private static func foreignKeys(
        for entry: SchemaEnrollment.AssociationEntry,
        in db: Database
    ) throws -> [ForeignKeyInfo] {
        try db.foreignKeys(on: entry.origin).filter { $0.destinationTable == entry.destination }
    }

    private static func resolves(_ entry: SchemaEnrollment.AssociationEntry, in db: Database) throws -> Bool {
        let keys = try foreignKeys(for: entry, in: db)
        guard let originColumns = entry.originColumns else { return keys.count == 1 }
        return keys.contains { $0.originColumns == originColumns }
    }
}
