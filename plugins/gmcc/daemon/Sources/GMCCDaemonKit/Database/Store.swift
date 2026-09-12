import Foundation
import GRDB

// StoreError lives in StoreError.swift; PersistedEvent in PersistedEvent.swift.

/// SQLite access layer. The daemon is the ONLY caller — every other client
/// (gmcc_hook, gmcc_mcp, GMVibes) reaches the db through the socket. DatabaseQueue serializes all access,
/// making the single-writer invariant structural rather than conventional.
///
/// Domain methods live in per-family extensions (Store+Context, Store+Session,
/// Store+Prompt, Store+Artifact, Store+FileChange, Store+Event, Store+Backup);
/// this file holds lifecycle, health and maintenance, plus the forward layer
/// onto StoreCore.
///
/// Store's five responsibilities after the StoreCore extraction — the fifth is
/// the one that surprises people:
///   1. Own `dbQueue` and the transaction boundary (every public verb).
///   2. Own `core`, migrations, lifecycle, health reads, WAL checkpoint.
///   3. Host the cross-family helper forwards. 15 of them are named directly
///      by tests, so this layer is permanent — but under the (db, core) swap
///      it is no longer on the repository-to-repository call path.
///   4. Host the two hand mappers that cannot convert: `Store.dopeScopeRow`
///      (test-pinned as a non-throwing function value) and `Store.sessionStub`
///      (computed last_activity_at).
///   5. Host ~624 lines of four-phase verb orchestration (Store+DopeRepoVerbs,
///      Store+DiagramRepoVerbs): db read → pure projection → filesystem work
///      with NO lock held → db write. A repository by construction holds an
///      open `Database`, so this genuinely cannot move into one.
///
/// Consequently this refactor does NOT make Store small. The deliverable is
/// the dependency direction — repositories stop holding a Store — not the line
/// count.
public final class Store: @unchecked Sendable {
    let dbQueue: DatabaseQueue

    public let dbPath: String

    /// The shared write core. `let`, never `var`: a recreated core would
    /// silently drop an already-registered event sink, and the daemon would go
    /// mute while still looking healthy. Held strongly so the retain graph
    /// Server → Store → core keeps the post-commit closure alive for exactly
    /// the lifetime it had when appendEvent lived here.
    let core = StoreCore()

    /// Post-commit event fan-out. See StoreCore.eventSink for the contract.
    ///
    /// This MUST stay a real get/set forward. Server assigns it AFTER Store
    /// construction, so a stored property copied into the core at init would
    /// accept the assignment and quietly discard it — every SUBSCRIBE client,
    /// GMVibes live refresh and watcher rebuild would go dead with the suite
    /// still green. EventSinkTests.testSinkIsReassignableAndClearable exists
    /// for exactly this.
    public var eventSink: ((PersistedEvent) -> Void)? {
        get { core.eventSink }
        set { core.eventSink = newValue }
    }

    public init(path: String) throws {
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

    public func migrate() throws {
        try Migrations.migrator.migrate(dbQueue)
    }

    // MARK: - StoreCore forwards
    //
    // Bodies live on StoreCore; these exist because callers name them here.
    // The instance forwards are NOT optional dressing: KbiteExportImportTests
    // calls `store.insertBase(db, table:extra:)` directly, so it must remain an
    // instance method with this exact signature, defaulted parameters and
    // @discardableResult included. The statics keep ~100 internal `Store.X`
    // references and 45 test call sites compiling unchanged —
    // rewriting those to `StoreCore.` would be churn with no structural payoff.

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

    public static func isoNow() -> String { StoreCore.isoNow() }

    static func newUuid() -> String { StoreCore.newUuid() }

    public static func jsonPayload(_ object: [String: Any]) -> String? {
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

    public func recordDaemonStart() throws {
        _ = try dbQueue.write { db in
            try self.appendEvent(db, kind: .daemonStart, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    public func recordDaemonStop() throws {
        _ = try dbQueue.write { db in
            try self.appendEvent(db, kind: .daemonStop, payload: Store.jsonPayload(["pid": Int(getpid())]))
        }
    }

    // MARK: - Health reads

    public func schemaVersion() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
        }
    }

    public func tableCounts() throws -> [TableCount] {
        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                ORDER BY name
                """)
            return try tables.map { table in
                TableCount(name: table,
                           count: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0)
            }
        }
    }

    // MARK: - Maintenance (SHUTDOWN)

    /// Truncate the WAL back into the main db file — part of the SHUTDOWN
    /// contract ("checkpoint WAL").
    public func checkpointTruncate() throws {
        try dbQueue.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

    public func closeDatabase() throws {
        try dbQueue.close()
    }
}
