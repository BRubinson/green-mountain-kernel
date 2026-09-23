import Foundation
import GRDB
import XCTest

/// The drift net over the enrolled persistence surface.
///
/// Every assertion reads the LIVE schema of the booted kernel through the
/// shared read-only handle, so what passes here passes against the database the
/// daemon actually migrated, not against a hand-kept copy of it.
final class SchemaEnrollmentTests: KernelBackedTestCase {

    /// One mirror record per table, decoding two fabricated rows.
    ///
    /// PROVES three drifts, each a decode failure naming its table: a column the
    /// record declares that the table LOST, cross-affinity type drift, and
    /// nullability drift (the second row NULLs every column the schema calls
    /// nullable). DOES NOT PROVE a column the table GAINED — `Decodable` ignores
    /// keys it never asks for — and the fabricated values assume primitive
    /// property types: a `Date` or `RawRepresentable` property fails on "1".
    func testEveryRecordMatchesItsTable() throws {
        XCTAssertEqual(SchemaEnrollment.records.count, 72, "a table mirror left the roster or never joined it")

        try env.readOnlyDatabase()
            .read { db in
                for entry in SchemaEnrollment.records {
                    let columns = try db.columns(in: entry.table)
                    XCTAssertFalse(columns.isEmpty, entry.table)
                    XCTAssertNoThrow(try entry.decode(Self.fabricatedRow(for: columns)), entry.table)
                    XCTAssertNoThrow(
                        try entry.decode(Self.nullableRow(for: columns)),
                        "\(entry.table): a nullable column is declared non-optional"
                    )
                }
            }
    }

    /// The roster's three fences, counted against the Sources tree itself.
    ///
    /// The `count ==` literals compare against a hand-written array, so an
    /// omission moves neither side. This counts the declarations on disk, which
    /// is the only side an author actually edits.
    func testRosterCountsMatchTheSourceTree() throws {
        let entities = try Self.entitiesDirectory()
        var tables = 0
        var associations = 0
        for url in try Self.swiftFiles(under: entities) {
            let source = try String(contentsOf: url, encoding: .utf8)
            tables += Self.matchCount(of: #"static let databaseTableName"#, in: source)
            associations += Self.matchCount(
                of: #"static let [A-Za-z0-9_]+ = (hasMany|hasOne|belongsTo)"#,
                in: source
            )
        }
        XCTAssertEqual(
            SchemaEnrollment.records.count,
            tables,
            "Entities declares \(tables) tables; the roster enrolls \(SchemaEnrollment.records.count)"
        )
        XCTAssertEqual(
            SchemaEnrollment.associations.count,
            associations,
            "Entities declares \(associations) associations; "
                + "the roster enrolls \(SchemaEnrollment.associations.count)"
        )
    }

    // MARK: - Source tree

    /// `Sources/Persistence/Entities`, found by walking up from this file.
    ///
    /// - Returns: The URL to the Entities directory.
    /// - Throws: `XCTSkip` if the directory cannot be found above the test file.
    private static func entitiesDirectory() throws -> URL {
        let suffix = "gmk/Sources/Persistence/Entities"
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(suffix, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        throw XCTSkip("no \(suffix) above \(#filePath): the fence needs the checkout it was built from")
    }

    /// Lists Swift source files in a directory.
    ///
    /// - Parameter directory: The directory to search.
    /// - Returns: Array of URLs for `.swift` files.
    /// - Throws: Any file system error.
    private static func swiftFiles(under directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    /// Counts regex pattern matches in source code.
    ///
    /// - Parameters:
    ///   - pattern: A regex pattern string.
    ///   - source: The source code to search.
    /// - Returns: The number of matches found; 0 if regex compilation fails.
    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    /// Every association's foreign key resolves to exactly one candidate.
    ///
    /// GRDB traps rather than throwing when inference finds none or several, so
    /// this reads the `foreign_key_list` pragma and never prepares a request.
    func testEveryAssociationResolvesItsForeignKey() throws {
        XCTAssertEqual(SchemaEnrollment.associations.count, 154, "an association left the roster or never joined it")

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
        XCTAssertEqual(SchemaEnrollment.composites.count, 50, "a composite left the roster or never joined it")

        try env.readOnlyDatabase()
            .read { db in
                for entry in SchemaEnrollment.composites {
                    let sql = try entry.prepare(db)
                    XCTAssertFalse(sql.isEmpty, entry.label)
                }
            }
    }

    /// The resource listing never plans the content column into its main
    /// statement.
    ///
    /// `resource_file_content` is the largest column in the schema and lives one
    /// `including(all:)` away, so a prefetch downgraded to a join would pull it
    /// in here. The child statement's own select list is asserted over a live
    /// fetch in `ComposedReadTests`, which has rows to make the prefetch run.
    func testResourceListingKeepsContentOutOfItsMainStatement() throws {
        let entry = try XCTUnwrap(
            SchemaEnrollment.composites.first { $0.label == "KbiteResourceWithFiles" },
            "the resource composite left the roster"
        )

        try env.readOnlyDatabase()
            .read { db in
                let sql = try entry.prepare(db)
                XCTAssertTrue(sql.contains("kbite_resource"), sql)
                XCTAssertFalse(
                    sql.contains("resource_file_content"),
                    "the content column reached the main statement: \(sql)"
                )
            }
    }

    // MARK: - Fabrication

    /// A row carrying one value per column, typed by declared affinity.
    ///
    /// - Parameter columns: The columns to populate.
    /// - Returns: A `Row` with one fabricated value per column.
    private static func fabricatedRow(for columns: [ColumnInfo]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [:]
        for column in columns {
            values[column.name] = dummy(forDeclaredType: column.type)
        }
        return Row(values)
    }

    /// A row with every nullable column NULL to test non-null declarations.
    ///
    /// Primary keys keep their values: SQLite reports an INTEGER PRIMARY KEY
    /// rowid alias as nullable, but no row ever carries NULL there. A record
    /// declaring a nullable column as non-optional will throw on this row.
    ///
    /// - Parameter columns: The columns to populate.
    /// - Returns: A `Row` with nulls for nullable columns.
    private static func nullableRow(for columns: [ColumnInfo]) -> Row {
        var values: [String: (any DatabaseValueConvertible)?] = [:]
        for column in columns {
            let keepsValue = column.isNotNull || column.primaryKeyIndex > 0
            values[column.name] = keepsValue ? dummy(forDeclaredType: column.type) : nil
        }
        return Row(values)
    }

    /// SQLite affinity is a prefix rule; BLOB and an undeclared type land on `Data`.
    ///
    /// - Parameter declaredType: The column's declared type string.
    /// - Returns: A value conforming to `DatabaseValueConvertible`.
    private static func dummy(forDeclaredType declaredType: String) -> any DatabaseValueConvertible {
        let type = declaredType.uppercased()
        if type.hasPrefix("INT") { return Int64(1) }
        if type.hasPrefix("TEXT") || type.hasPrefix("CHAR") || type.hasPrefix("CLOB") { return "1" }
        if type.hasPrefix("REAL") || type.hasPrefix("FLOA") || type.hasPrefix("DOUB") { return 1.0 }
        return Data()
    }

    // MARK: - Foreign keys

    /// Retrieves foreign keys for an association's origin table.
    ///
    /// - Parameters:
    ///   - entry: The association entry.
    ///   - db: The database to query.
    /// - Returns: Array of foreign keys targeting the entry's destination table.
    /// - Throws: Any database error.
    private static func foreignKeys(
        for entry: SchemaEnrollment.AssociationEntry,
        in db: Database
    ) throws -> [ForeignKeyInfo] {
        try db.foreignKeys(on: entry.origin).filter { $0.destinationTable == entry.destination }
    }

    /// Checks if an association's foreign key exists and matches its declared columns.
    ///
    /// - Parameters:
    ///   - entry: The association entry.
    ///   - db: The database to query.
    /// - Returns: `true` if the foreign key exists and matches the entry's origin columns.
    /// - Throws: Any database error.
    private static func resolves(_ entry: SchemaEnrollment.AssociationEntry, in db: Database) throws -> Bool {
        let keys = try foreignKeys(for: entry, in: db)
        guard let originColumns = entry.originColumns else { return keys.count == 1 }
        return keys.contains { $0.originColumns == originColumns }
    }
}
