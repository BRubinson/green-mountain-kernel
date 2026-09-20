import Foundation
import GRDB

// StoreError lives in StoreError.swift; PersistedEvent in PersistedEvent.swift.

/// SQLite access layer. ONE PROCESS OPENS THIS DB AND CANNOT BE TWO:
/// `KernelWriter` is the sole `Store(path:)` site and consumes a token only a
/// won `flock` can produce. In-process callers reach verbs through the same
/// public methods the socket handlers call, and `DatabaseQueue` serializes every
/// access as the one connection pool. The transaction boundary lives in
/// `StoreBoundary.swift`, so a verb called inside `inTransaction` enlists rather
/// than trapping. This file holds lifecycle, health, the StoreCore forwards and
/// the four-phase verb orchestration a repository cannot host.
final class Store: @unchecked Sendable {
    let dbQueue: DatabaseQueue

    let dbPath: String

    /// The shared write core. `let`, never `var`: a recreated core would
    /// silently drop every already-registered subscriber, and the daemon would
    /// go mute while still looking healthy. Held strongly so the retain graph
    /// Server → Store → core keeps the post-commit closures alive for exactly
    /// the lifetime they had when appendEvent lived here.
    let core = StoreCore()

    /// Register a post-commit event consumer. See `StoreCore.subscribe` for what
    /// a subscriber is permitted to do — it is narrow, and the fan-out runs on
    /// the writer thread inside the commit hook.
    ///
    /// THERE IS DELIBERATELY NO `eventSink` SETTER. A settable property lets a
    /// second assignment displace the first with no error anywhere, and two
    /// consumers exist: the socket server and the in-process app host.
    @discardableResult
    func subscribeToEvents(_ sink: @escaping (PersistedEvent) -> Void) -> UUID {
        core.subscribe(sink)
    }

    func unsubscribeFromEvents(_ token: UUID) {
        core.unsubscribe(token)
    }

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

    @discardableResult
    func insertBase(
        _ db: Database,
        table: String,
        uuid: String? = nil,
        now: String? = nil,
        extra: [String: (any DatabaseValueConvertible)?]
    ) throws -> String {
        try core.insertBase(db, table: table, uuid: uuid, now: now, extra: extra)
    }

    func updateBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64,
        set: [String: (any DatabaseValueConvertible)?]
    ) throws {
        try core.updateBase(db, table: table, uuid: uuid, expectedVersion: expectedVersion, set: set)
    }

    func deleteBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64
    ) throws {
        try core.deleteBase(db, table: table, uuid: uuid, expectedVersion: expectedVersion)
    }

    @discardableResult
    func appendEvent(
        _ db: Database,
        kind: DaemonEventKind,
        subjectUuid: String? = nil,
        payload: String? = nil
    ) throws -> String {
        try core.appendEvent(db, kind: kind, subjectUuid: subjectUuid, payload: payload)
    }

    func touchSession(_ db: Database, uuid: String) throws {
        try core.touchSession(db, uuid: uuid)
    }

    static func isoNow() -> String { StoreCore.isoNow() }

    static func newUuid() -> String { StoreCore.newUuid() }

    static func jsonPayload(_ object: [String: Any]) -> String? {
        StoreCore.jsonPayload(object)
    }

    static func slugStorageSegment(_ raw: String) -> String {
        StoreCore.slugStorageSegment(raw)
    }

    static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
        try StoreCore.normalizeRepoRelativePath(raw, repoRoot: repoRoot)
    }

    static let maxNarrativeBytes = StoreCore.maxNarrativeBytes

    static let findingReadThreshold = StoreCore.findingReadThreshold

    // MARK: - Lifecycle events

    func recordDaemonStart() throws {
        _ = try boundary { db in
            try self.appendEvent(db, kind: .daemonStart, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    func recordDaemonStop() throws {
        _ = try boundary { db in
            try self.appendEvent(db, kind: .daemonStop, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    // MARK: - Health reads

    func schemaVersion() throws -> Int {
        try boundaryRead { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
        }
    }

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

    /// Truncate the WAL back into the main db file — part of the SHUTDOWN
    /// contract ("checkpoint WAL").
    ///
    /// Keeps `writeWithoutTransaction` and is the ONLY place in the module that
    /// does. A checkpoint inside a transaction is illegal in SQLite, so this
    /// deliberately does not route through `boundary` — and it refuses when a
    /// caller has one open rather than failing deeper in with a SQLite error
    /// whose text would not name the cause.
    func checkpointTruncate() throws {
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "checkpointTruncate")
        }
        try dbQueue.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

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
