import Foundation
import GRDB

// StoreError lives in StoreError.swift; PersistedEvent in PersistedEvent.swift.

/// SQLite access layer.
///
/// ONE PROCESS OPENS THIS DB: sole writer via `KernelWriter`'s `Store(path:)` with `flock`-won token.
/// In-process and socket callers share public methods; `DatabaseQueue` serializes access as one pool.
/// Transaction boundary in `StoreBoundary.swift` enlists verbs rather than trapping on re-entrance.
/// File manages lifecycle, health, StoreCore forwards, and four-phase verb orchestration.
final class Store: Sendable {
    let dbQueue: DatabaseQueue

    let dbPath: String

    /// The shared write core.
    ///
    /// `let`, never `var`: a recreated core would silently drop every
    /// already-registered subscriber, and the daemon would go mute while still
    /// looking healthy. Held strongly so the retain graph Server → Store → core
    /// keeps the post-commit closures alive for exactly the lifetime they had
    /// when appendEvent lived here.
    let core = StoreCore()

    /// Register a post-commit event consumer.
    ///
    /// See `StoreCore.subscribe` for what a subscriber is permitted to do — it
    /// is narrow, and the fan-out runs on the writer thread inside the commit
    /// hook. THERE IS DELIBERATELY NO `eventSink` SETTER. A settable property
    /// lets a second assignment displace the first with no error anywhere, and
    /// two consumers exist: the socket server and the in-process app host.
    ///
    /// - Parameter sink: The closure called with each committed event.
    /// - Returns: A token to pass to `unsubscribeFromEvents(_:)`.
    @discardableResult
    func subscribeToEvents(_ sink: @escaping @Sendable (PersistedEvent) -> Void) -> UUID {
        core.subscribe(sink)
    }

    /// Unsubscribe from post-commit events using a subscription token.
    ///
    /// - Parameter token: The token returned by `subscribeToEvents(_:)`.
    func unsubscribeFromEvents(_ token: UUID) {
        core.unsubscribe(token)
    }

    /// Opens the SQLite database at the given path.
    ///
    /// - Parameter path: The file system path to the database file.
    /// - Throws: `DatabaseError` if the file cannot be opened or configured.
    init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // GRDB enables foreign_keys by default; WAL is opt-in.
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            // The kbite_resource_file FTS5 sync triggers must also fire when
            // rows disappear via FK CASCADE (SQLite's default is OFF).
            try db.execute(sql: "PRAGMA recursive_triggers=ON")
        }
        self.dbPath = path
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
    }

    /// Migrate the database schema to the current version.
    ///
    /// - Throws: `DatabaseError` if any migration fails.
    func migrate() throws {
        try Migrations.migrator.migrate(dbQueue)
    }

    // MARK: - StoreCore forwards
    //
    // Bodies live on StoreCore; these exist because callers name them here.
    // The instance forwards are not dressing: KbiteExportImportTests calls
    // `store.insertBase(db, table:extra:)` directly, so it must stay an instance
    // method with this exact signature, defaulted parameters and
    // @discardableResult included.

    /// Insert a row with the five BaseEntity columns plus extra columns.
    ///
    /// - Parameters:
    ///   - db: The transaction database.
    ///   - table: The domain table, by its SQL name.
    ///   - extra: Column values keyed by column name.
    ///   - uuid: The row's uuid; generated if `nil`.
    ///   - now: The creation timestamp; current time if `nil`.
    /// - Returns: The uuid of the inserted row.
    /// - Throws: `DatabaseError` if the insert fails.
    @discardableResult
    func insertBase(
        _ db: Database,
        table: String,
        extra: [String: (any DatabaseValueConvertible)?],
        uuid: String? = nil,
        now: String? = nil
    ) throws -> String {
        try core.insertBase(db, table: table, extra: extra, uuid: uuid, now: now)
    }

    /// Update a row with optimistic concurrency control via version gates.
    ///
    /// - Parameters:
    ///   - db: The transaction database.
    ///   - table: The domain table, by its SQL name.
    ///   - uuid: The row's uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - set: Column values keyed by column name to update.
    /// - Throws: `StoreError.versionConflict` when the version is stale; `StoreError.notFound` when the row does not exist.
    func updateBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64,
        set: [String: (any DatabaseValueConvertible)?]
    ) throws {
        try core.updateBase(db, table: table, uuid: uuid, expectedVersion: expectedVersion, set: set)
    }

    /// Delete a row with optimistic concurrency control via version gates.
    ///
    /// - Parameters:
    ///   - db: The transaction database.
    ///   - table: The domain table, by its SQL name.
    ///   - uuid: The row's uuid.
    ///   - expectedVersion: The version the caller last read.
    /// - Throws: `StoreError.versionConflict` when the version is stale; `StoreError.notFound` when the row does not exist.
    func deleteBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64
    ) throws {
        try core.deleteBase(db, table: table, uuid: uuid, expectedVersion: expectedVersion)
    }

    /// Append a daemon_event row and stage it for the post-commit sink.
    ///
    /// - Parameters:
    ///   - db: The transaction database.
    ///   - kind: The event kind.
    ///   - subjectUuid: The uuid of the entity this event concerns, if any.
    ///   - payload: Optional JSON data associated with this event.
    /// - Returns: The uuid of the appended event.
    /// - Throws: `DatabaseError` if the insert fails.
    @discardableResult
    func appendEvent(
        _ db: Database,
        kind: DaemonEventKind,
        subjectUuid: String? = nil,
        payload: String? = nil
    ) throws -> String {
        try core.appendEvent(db, kind: kind, subjectUuid: subjectUuid, payload: payload)
    }

    /// Advance a session's recency without bumping its version.
    ///
    /// - Parameters:
    ///   - db: The transaction database.
    ///   - uuid: The session's uuid.
    /// - Throws: `DatabaseError` if the update fails.
    func touchSession(_ db: Database, uuid: String) throws {
        try core.touchSession(db, uuid: uuid)
    }

    /// The current time as an ISO-8601 Z timestamp.
    ///
    /// - Returns: An ISO-8601 formatted timestamp string.
    static func isoNow() -> String { StoreCore.isoNow() }

    /// Generate a new UUID as a lowercased string.
    ///
    /// - Returns: A UUID string in lowercase.
    static func newUuid() -> String { StoreCore.newUuid() }

    /// Serialize an object to JSON for storage in daemon event payloads.
    ///
    /// - Parameter object: The dictionary to encode.
    /// - Returns: A JSON string, or `nil` if encoding fails.
    static func jsonPayload(_ object: [String: Any]) -> String? {
        StoreCore.jsonPayload(object)
    }

    /// Convert a prompt name to a storage-safe slug.
    ///
    /// - Parameter raw: The raw name to convert.
    /// - Returns: A slugified version safe for use in file paths.
    static func slugStorageSegment(_ raw: String) -> String {
        StoreCore.slugStorageSegment(raw)
    }

    /// Normalize a repository-relative path.
    ///
    /// - Parameters:
    ///   - raw: The raw path to normalize.
    ///   - repoRoot: The repository root directory.
    /// - Returns: The normalized path.
    /// - Throws: `PathError` if the path cannot be normalized.
    static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
        try StoreCore.normalizeRepoRelativePath(raw, repoRoot: repoRoot)
    }

    static let maxNarrativeBytes = StoreCore.maxNarrativeBytes

    static let findingReadThreshold = StoreCore.findingReadThreshold

    // MARK: - Lifecycle events

    /// Record a daemon start event in the database.
    ///
    /// - Throws: `DatabaseError` if the event cannot be recorded.
    func recordDaemonStart() throws {
        _ = try boundary { db in
            try self.appendEvent(db, kind: .daemonStart, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    /// Record a daemon stop event in the database.
    ///
    /// - Throws: `DatabaseError` if the event cannot be recorded.
    func recordDaemonStop() throws {
        _ = try boundary { db in
            try self.appendEvent(db, kind: .daemonStop, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    // MARK: - Health reads

    /// The current database schema version.
    ///
    /// - Returns: The latest migration version applied, or zero if none.
    /// - Throws: `DatabaseError` if the query fails.
    func schemaVersion() throws -> Int {
        try boundaryRead { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
        }
    }

    /// Table names and row counts in the database.
    ///
    /// - Returns: An array of `TableCount` for each user-defined table.
    /// - Throws: `DatabaseError` if the query fails.
    func tableCounts() throws -> [TableCount] {
        try boundaryRead { db in
            let tables = try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                    ORDER BY name
                    """
            )
            return try tables.map { table in
                TableCount(
                    name: table,
                    count: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                )
            }
        }
    }

    // MARK: - Maintenance (SHUTDOWN)

    /// Truncate the WAL back into the main db file (part of SHUTDOWN contract).
    ///
    /// Keeps `writeWithoutTransaction` and is the ONLY place in the module that
    /// does. A checkpoint inside a transaction is illegal in SQLite, so this
    /// deliberately does not route through `boundary` — and it refuses when a
    /// caller has one open rather than failing deeper in with a SQLite error
    /// whose text would not name the cause.
    ///
    /// - Throws: `StoreError.notComposable` if called from inside a transaction.
    func checkpointTruncate() throws {
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "checkpointTruncate")
        }
        try dbQueue.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

    /// Close the database connection.
    ///
    /// - Throws: `StoreError.notComposable` if called from inside a transaction; `DatabaseError` if the close fails.
    func closeDatabase() throws {
        // Closing the queue from inside one of its own transactions is the same
        // re-entrancy trap as `backup` and `checkpointTruncate`, and it is
        // reachable now that in-process callers exist: a termination path that
        // composed its final flush and then closed would take the process down
        // with a trap instead of shutting down cleanly.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "closeDatabase")
        }
        try dbQueue.close()
    }
}
