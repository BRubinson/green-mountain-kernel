import Foundation
import GRDB
import Synchronization

/// The transaction-scoped write core: the five shared primitives, the
/// post-commit event sink, and the shared static contracts.
///
/// Holds NO DatabaseQueue and exposes NO verb, and that absence is the point.
/// A repository handed a `StoreCore` has no path back to `dbQueue.write`, so
/// re-entering a transaction is not expressible — and GRDB 7 TRAPS on
/// re-entrancy, killing the daemon rather than returning an error. The
/// subscriber table is the only stored state.
final class StoreCore: Sendable {

    /// Post-commit event fan-out, registered via GRDB's
    /// afterNextTransaction(onCommit:), so events fire only for committed
    /// transactions and never while the db lock is held.
    ///
    /// A TABLE, not one closure: a sink lets a second consumer displace the
    /// first. `emit` runs in the commit hook: a blocking subscriber stalls
    /// the writer, a callback deadlocks. Hand off immediately and use the
    /// mutex to make cross-thread subscribe/emit provably safe.
    private let subscribers = Mutex<[UUID: @Sendable (PersistedEvent) -> Void]>([:])

    /// Registers a post-commit event consumer and returns its subscription token.
    ///
    /// Subscriptions must be SYMMETRIC: a subscriber that captures `self` and
    /// never unsubscribes outlives whatever it belonged to.
    ///
    /// - Parameter sink: A closure called with each committed event after the
    ///   transaction's post-commit hook.
    /// - Returns: A token to pass to `unsubscribe(_:)` to stop receiving events.
    func subscribe(_ sink: @escaping @Sendable (PersistedEvent) -> Void) -> UUID {
        let token = UUID()
        subscribers.withLock { $0[token] = sink }
        return token
    }

    /// Removes a subscription from the event fan-out.
    ///
    /// - Parameter token: The token returned by `subscribe(_:)`.
    func unsubscribe(_ token: UUID) {
        subscribers.withLock { _ = $0.removeValue(forKey: token) }
    }

    /// Broadcasts an event to all registered subscribers.
    ///
    /// Called from the commit hook only. The snapshot-then-call shape is
    /// deliberate: a subscriber that unsubscribes from inside its own callback
    /// would otherwise mutate the dictionary being iterated, and holding the
    /// lock across the callbacks would deadlock that same subscriber.
    ///
    /// - Parameter event: The event to broadcast to all subscribers.
    func emit(_ event: PersistedEvent) {
        let sinks = subscribers.withLock { Array($0.values) }
        for sink in sinks { sink(event) }
    }

    // MARK: - Base-field helpers

    /// Sole timestamp source: seconds-precision ISO-8601 Z. EVENT_LIST time
    /// filters compare lexicographically, which is correct only while every
    /// writer emits exactly this format.
    // ISO8601DateFormatter is documented thread-safe; the annotation only
    // silences Swift 6's conservative Sendable check.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    /// Returns the current time as an ISO-8601 timestamp in UTC.
    ///
    /// - Returns: A seconds-precision ISO-8601 Z-terminated timestamp.
    static func isoNow() -> String {
        isoFormatter.string(from: Date())
    }

    /// Returns an ISO-8601 timestamp offset by the given seconds.
    ///
    /// Used only by the test lock's LEASE mode — the degraded liveness path
    /// for a holder that cannot keep a file descriptor open. The flock probe
    /// is the primary test and needs no clock at all.
    ///
    /// - Parameter offsetSeconds: Seconds to offset from the current time.
    /// - Returns: A seconds-precision ISO-8601 Z-terminated timestamp.
    static func isoNow(offsetSeconds: Int) -> String {
        isoFormatter.string(from: Date().addingTimeInterval(TimeInterval(offsetSeconds)))
    }

    /// Parses an ISO-8601 timestamp to a `Date`.
    ///
    /// Returns nil rather than throwing: every caller is comparing against a
    /// deadline, and an unparseable stamp must degrade to "no opinion" rather
    /// than to a decision — reading a bad lease as expired would break a live
    /// holder's lock.
    ///
    /// - Parameter value: An ISO-8601 timestamp, as written by `isoNow()`.
    /// - Returns: The parsed date, or nil if the timestamp is malformed.
    static func parseIso(_ value: String) -> Date? {
        isoFormatter.date(from: value)
    }

    /// Generates a new lowercase UUID string.
    ///
    /// - Returns: A new randomly generated UUID in lowercase string form.
    static func newUuid() -> String {
        UUID().uuidString.lowercased()
    }

    /// Normalizes a repository-relative path string.
    ///
    /// Forwards to `RepoRelativePath.normalize` in the base layer. Kept so
    /// every existing call site remains unchanged.
    ///
    /// - Parameters:
    ///   - raw: The path string to normalize.
    ///   - repoRoot: The repository root path.
    /// - Returns: The normalized path.
    /// - Throws: `PathError` if the path cannot be normalized.
    static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
        try RepoRelativePath.normalizeRepoRelativePath(raw, repoRoot: repoRoot)
    }

    /// Converts a string to a storage-safe slug.
    ///
    /// The storage-path analogue of GitHead.sessionCode: forward-only and
    /// lossy, NEVER un-slugged. Applied when deriving a prompt's gmfs folder
    /// segment so names with spaces/slashes can't produce paths the
    /// MemoryWatcher's exact-match resolution would miss. Case is preserved
    /// (lowercasing would change more than needed). Existing rows are never
    /// rewritten.
    ///
    /// - Parameter raw: The string to convert to a slug.
    /// - Returns: A storage-safe slug, or `"prompt"` if the input yields nothing.
    static func slugStorageSegment(_ raw: String) -> String {
        var slug = ""
        for ch in raw {
            if ch.isASCII, ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" {
                slug.append(ch)
            } else if !slug.hasSuffix("_") {
                slug.append("_")
            }
        }
        while slug.contains("__") { slug = slug.replacingOccurrences(of: "__", with: "_") }
        // ASCII-only by construction, so 80 characters == 80 bytes (the gmfs
        // folder-name budget). Cap BEFORE trimming so truncation can't leave
        // a trailing separator.
        if slug.count > 80 { slug = String(slug.prefix(80)) }
        while let first = slug.first, first == "_" || first == "." { slug.removeFirst() }
        while let last = slug.last, last == "_" || last == "." { slug.removeLast() }
        return slug.isEmpty ? "prompt" : slug
    }

    /// Shared cap for narrative report text (exploration/review overview and
    /// finding bodies) — the same 2 MB budget as architecture change_code.
    static let maxNarrativeBytes = 2 * 1024 * 1024

    /// The consumption threshold of the 0–999 finding-rating scale: GETs
    /// return full rows under it (plus every unranked row) and stubs at or
    /// above it.
    static let findingReadThreshold = 100

    /// Serializes a dictionary to a JSON payload string.
    ///
    /// Builds the payload with a real serializer so embedded quotes and
    /// backslashes in values (file paths) can't produce malformed rows.
    ///
    /// - Parameter object: The dictionary to encode as JSON.
    /// - Returns: A JSON string, or nil if serialization fails.
    static func jsonPayload(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Write primitives

    /// Advances a session's last-activity time without changing its version.
    ///
    /// Prompt/file-change writes advancing updated_at must never invalidate
    /// a session version an editor is holding (spurious VERSION_CONFLICTs in
    /// the GMVibes session editor). The one place updated_at and version are
    /// not in lockstep. This operation is deliberately distinct from updateBase.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The session's identifier.
    /// - Throws: A database error if the update fails.
    func touchSession(_ db: Database, uuid: String) throws {
        try db.execute(
            sql: "UPDATE session SET updated_at = ? WHERE uuid = ?",
            arguments: [StoreCore.isoNow(), uuid]
        )
    }

    /// Inserts a row with base entity columns and additional custom columns.
    ///
    /// Inserts the five BaseEntity columns (uuid, version, created_at,
    /// updated_at) plus any `extra` columns. Returns the row's uuid, freshly
    /// generated unless `uuid` is supplied — callers pass a gmfs uuid to keep
    /// db ↔ gmfs joins trivial.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - table: The target table name.
    ///   - extra: Additional column values keyed by column name.
    ///   - uuid: The row's identifier, or nil to generate one.
    ///   - now: The creation timestamp, or nil to use the current time.
    /// - Returns: The uuid of the inserted row.
    /// - Throws: A database error if the insert fails.
    @discardableResult
    func insertBase(
        _ db: Database,
        table: String,
        extra: [String: (any DatabaseValueConvertible)?],
        uuid: String? = nil,
        now: String? = nil
    ) throws -> String {
        let rowUuid = uuid ?? StoreCore.newUuid()
        let now = now ?? StoreCore.isoNow()
        let columns = ["uuid", "version", "created_at", "updated_at"] + extra.keys.sorted()
        let values: [(any DatabaseValueConvertible)?] =
            [rowUuid, 0, now, now] + extra.keys.sorted().map { extra[$0] ?? nil }
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns.joined(separator: ", "))) VALUES (\(placeholders))"
        try db.execute(sql: sql, arguments: StatementArguments(values))
        return rowUuid
    }

    /// Updates a row with optimistic concurrency control.
    ///
    /// Bumps version and updated_at; matches only when the caller's expected
    /// version is current. Zero rows changed is discriminated (same transaction)
    /// into NOT_FOUND vs VERSION_CONFLICT. This is the primary write primitive.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - table: The target table name.
    ///   - uuid: The row's identifier.
    ///   - expectedVersion: The version the caller last read.
    ///   - set: Column values to update, keyed by column name.
    /// - Throws: `StoreError.notFound` if the row doesn't exist; `StoreError.versionConflict` if the expected version is stale.
    func updateBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64,
        set: [String: (any DatabaseValueConvertible)?]
    ) throws {
        let keys = set.keys.sorted()
        let assignments = (keys.map { "\($0) = ?" } + ["version = version + 1", "updated_at = ?"])
            .joined(separator: ", ")
        let sql = "UPDATE \(table) SET \(assignments) WHERE uuid = ? AND version = ?"
        let values: [(any DatabaseValueConvertible)?] =
            keys.map { set[$0] ?? nil } + [StoreCore.isoNow(), uuid, expectedVersion]
        try db.execute(sql: sql, arguments: StatementArguments(values))
        guard db.changesCount == 0 else { return }
        guard
            let actual = try Int64.fetchOne(
                db,
                sql: "SELECT version FROM \(table) WHERE uuid = ?",
                arguments: [uuid]
            )
        else {
            throw StoreError.notFound(entity: table, key: uuid)
        }
        throw StoreError.versionConflict(entity: table, uuid: uuid, expected: expectedVersion, actual: actual)
    }

    /// Deletes a row with optimistic concurrency control.
    ///
    /// The DELETE twin of updateBase, with the same zero-rows discrimination
    /// into NOT_FOUND vs VERSION_CONFLICT. Nothing in the schema deleted a
    /// versioned row before dope's granular verbs. FK CASCADEs report no count
    /// here; callers wanting cascade accounting COUNT before deleting, in the
    /// same transaction.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - table: The target table name.
    ///   - uuid: The row's identifier.
    ///   - expectedVersion: The version the caller last read.
    /// - Throws: `StoreError.notFound` if the row doesn't exist; `StoreError.versionConflict` if the expected version is stale.
    func deleteBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64
    ) throws {
        try db.execute(
            sql: "DELETE FROM \(table) WHERE uuid = ? AND version = ?",
            arguments: [uuid, expectedVersion]
        )
        guard db.changesCount == 0 else { return }
        guard
            let actual = try Int64.fetchOne(
                db,
                sql: "SELECT version FROM \(table) WHERE uuid = ?",
                arguments: [uuid]
            )
        else {
            throw StoreError.notFound(entity: table, key: uuid)
        }
        throw StoreError.versionConflict(entity: table, uuid: uuid, expected: expectedVersion, actual: actual)
    }

    /// Appends an event to the daemon event log and stages it for broadcast.
    ///
    /// Append-only: version stays 0 and updated_at == created_at, so
    /// insertBase's defaults are exactly right. Staged for the post-commit sink
    /// to broadcast to all subscribers.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - kind: The event kind to record.
    ///   - subjectUuid: The subject of the event, or nil if not applicable.
    ///   - payload: The event payload as JSON, or nil if not applicable.
    /// - Returns: The uuid of the appended event.
    /// - Throws: A database error if the insert fails.
    @discardableResult
    func appendEvent(
        _ db: Database,
        kind: DaemonEventKind,
        subjectUuid: String? = nil,
        payload: String? = nil
    ) throws -> String {
        // One timestamp for both the row and the sink copy, so the live
        // broadcast and a later replay of the same event id never differ.
        let createdAt = StoreCore.isoNow()
        let uuid = try insertBase(
            db,
            table: "daemon_event",
            extra: [
                "kind": kind.rawValue,
                "subject_uuid": subjectUuid,
                "payload": payload,
            ],
            now: createdAt
        )
        let event = PersistedEvent(
            id: db.lastInsertedRowID,
            kind: kind.rawValue,
            subjectUuid: subjectUuid,
            payload: payload,
            createdAt: createdAt
        )
        db.afterNextTransaction(
            onCommit: { [weak self] _ in self?.emit(event) },
            onRollback: { _ in }
        )
        return uuid
    }
}
