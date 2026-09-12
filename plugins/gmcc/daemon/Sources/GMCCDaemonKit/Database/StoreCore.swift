import Foundation
import GRDB

/// The transaction-scoped write core: the five shared primitives, the
/// post-commit event sink, and the shared static contracts.
///
/// Holds NO DatabaseQueue and exposes NO verb. That absence is the entire
/// point. A repository handed a `StoreCore` has no path back to
/// `dbQueue.write`, so re-entering a transaction from inside one is not
/// expressible — and GRDB 7 TRAPS on re-entrancy (DatabaseQueue.swift,
/// "Database methods are not reentrant"), killing the daemon process rather
/// than returning an error to the client. Before this type, that safety was
/// convention enforced by a doc comment repeated in every repository.
///
/// `eventSink` is the only stored state here; the other four primitives close
/// over nothing but the `Database` they are passed.
///
/// Every body below is a VERBATIM relocation from Store.swift, comments
/// included. The invariants they encode (insertBase's twin keys.sorted(),
/// appendEvent's lastInsertedRowID adjacency and single timestamp,
/// touchSession's deliberate non-bump, updateBase/deleteBase's same-transaction
/// zero-rows discrimination) are all things a tidy-up can break with no test
/// failure — so they were moved, not retyped.
final class StoreCore: @unchecked Sendable {

    /// Post-commit event fan-out. appendEvent registers each event via GRDB's
    /// afterNextTransaction(onCommit:), so the sink fires only for committed
    /// transactions (a rolled-back write can never leak a phantom event) and
    /// never while the db lock is held. The server registers this once (through
    /// `Store.eventSink`, which is a real get/set forward onto this property)
    /// and broadcasts every kind to subscribers.
    var eventSink: ((PersistedEvent) -> Void)?

    // MARK: - Base-field helpers

    /// Sole timestamp source: seconds-precision ISO-8601 Z. EVENT_LIST time
    /// filters compare lexicographically, which is correct only while every
    /// writer emits exactly this format.
    // ISO8601DateFormatter is documented thread-safe; the annotation only
    // silences Swift 6's conservative Sendable check.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    public static func isoNow() -> String {
        isoFormatter.string(from: Date())
    }

    static func newUuid() -> String {
        UUID().uuidString.lowercased()
    }


    /// The comparison feature's join key contract: architecture change rows
    /// and file_change rows meet on this string, so both write paths run
    /// through this one normalizer. Purely lexical — NEVER touches the
    /// filesystem (live instance roots include paths that no longer exist,
    /// and architecture rows name files that don't exist yet).
    ///
    /// Relative paths are anchored by definition and pass through cleaned; an
    /// absolute path inside the instance root is stripped to repo-relative;
    /// an absolute path outside it is rejected (honest failure over a
    /// silently zero-match join).
    static func normalizeRepoRelativePath(_ raw: String, repoRoot: String) throws -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw StoreError.badRequest(detail: "file path is empty")
        }
        guard !path.contains("\0"), !path.contains("\n") else {
            throw StoreError.badRequest(detail: "file path contains control characters")
        }
        if path.hasPrefix("~/") {
            path = NSHomeDirectory() + String(path.dropFirst(1))
        }
        if path.hasPrefix("/") {
            var root = repoRoot
            while root.hasSuffix("/") { root = String(root.dropLast()) }
            guard root.count > 1, path == root || path.hasPrefix(root + "/") else {
                throw StoreError.badRequest(
                    detail: "path is not inside the instance root (\(repoRoot)): \(raw)")
            }
            path = String(path.dropFirst(root.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        let segments = path.split(separator: "/")
        guard !segments.contains("..") else {
            throw StoreError.badRequest(detail: "path escapes the repo root: \(raw)")
        }
        guard !path.isEmpty, path != "/" else {
            throw StoreError.badRequest(detail: "path resolves to the repo root: \(raw)")
        }
        return path
    }

    /// The storage-path analogue of GitHead.sessionCode: forward-only, lossy,
    /// NEVER un-slugged. Applied when deriving a prompt's ckfs folder segment
    /// so names with spaces/slashes can't produce paths the MemoryWatcher's
    /// exact-match resolution would miss. Case is preserved (lowercasing
    /// would change more than needed). Existing rows are never rewritten.
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
        // ASCII-only by construction, so 80 characters == 80 bytes (the ckfs
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

    /// daemon_event.payload is documented as JSON — always build it with a
    /// real serializer so embedded quotes/backslashes in values (file paths!)
    /// can't produce malformed rows.
    public static func jsonPayload(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Write primitives

    /// Advance a session's recency WITHOUT bumping its version — deliberately
    /// not updateBase. Prompt/file-change writes advancing updated_at must
    /// never invalidate a session version an editor is holding (spurious
    /// VERSION_CONFLICTs in the GMVibes session editor). The one place
    /// updated_at and version are not in lockstep.
    func touchSession(_ db: Database, uuid: String) throws {
        try db.execute(
            sql: "UPDATE session SET updated_at = ? WHERE uuid = ?",
            arguments: [StoreCore.isoNow(), uuid])
    }


    /// Insert a row with the five BaseEntity columns plus `extra` columns.
    /// Returns the row's uuid (freshly generated unless `uuid` is supplied —
    /// callers pass a ckfs uuid to keep db ↔ ckfs joins trivial).
    @discardableResult
    func insertBase(
        _ db: Database,
        table: String,
        uuid: String? = nil,
        now: String? = nil,
        extra: [String: (any DatabaseValueConvertible)?]
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

    /// Guarded update — THE optimistic-concurrency primitive. Bumps version
    /// and updated_at; matches only when the caller's expected version is
    /// current. Zero rows changed is discriminated (same transaction) into
    /// NOT_FOUND vs VERSION_CONFLICT.
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
        guard let actual = try Int64.fetchOne(
            db, sql: "SELECT version FROM \(table) WHERE uuid = ?", arguments: [uuid]
        ) else {
            throw StoreError.notFound(entity: table, key: uuid)
        }
        throw StoreError.versionConflict(entity: table, uuid: uuid, expected: expectedVersion, actual: actual)
    }

    /// Guarded delete — the DELETE twin of updateBase, with the same
    /// zero-rows discrimination into NOT_FOUND vs VERSION_CONFLICT. Nothing
    /// in the schema deleted a versioned row before dope's granular verbs.
    /// FK CASCADEs report no count here; callers wanting cascade accounting
    /// COUNT before deleting, in the same transaction.
    func deleteBase(
        _ db: Database,
        table: String,
        uuid: String,
        expectedVersion: Int64
    ) throws {
        try db.execute(
            sql: "DELETE FROM \(table) WHERE uuid = ? AND version = ?",
            arguments: [uuid, expectedVersion])
        guard db.changesCount == 0 else { return }
        guard let actual = try Int64.fetchOne(
            db, sql: "SELECT version FROM \(table) WHERE uuid = ?", arguments: [uuid]
        ) else {
            throw StoreError.notFound(entity: table, key: uuid)
        }
        throw StoreError.versionConflict(entity: table, uuid: uuid, expected: expectedVersion, actual: actual)
    }

    /// Append a daemon_event row and stage it for the post-commit sink.
    /// Append-only: version stays 0 and updated_at == created_at, so
    /// insertBase's defaults are exactly right.
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
        let uuid = try insertBase(db, table: "daemon_event", now: createdAt, extra: [
            "kind": kind.rawValue,
            "subject_uuid": subjectUuid,
            "payload": payload,
        ])
        let event = PersistedEvent(
            id: db.lastInsertedRowID,
            kind: kind.rawValue,
            subjectUuid: subjectUuid,
            payload: payload,
            createdAt: createdAt
        )
        db.afterNextTransaction(
            onCommit: { [weak self] _ in self?.eventSink?(event) },
            onRollback: { _ in }
        )
        return uuid
    }
}
