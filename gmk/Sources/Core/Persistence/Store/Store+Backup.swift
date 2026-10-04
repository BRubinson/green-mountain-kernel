import Foundation
import GRDB

// BACKUP — SQLite Online Backup API via GRDB, into ~/gmfs/backups/.
// Required before real prompt content trusts the db.

extension Store {
    /// Back up the database to a timestamped file.
    ///
    /// `recordEvent` appends a `backup` row to the event log, unless false for pre-migration
    /// snapshots (when schema versions conflict between database and binary).
    /// - Parameter recordEvent: Whether to append a backup event to the log; defaults to true.
    /// - Returns: The backup response with path and size.
    /// - Throws: File system, database queue, or event log errors.
    func backup(recordEvent: Bool = true) throws -> BackupResponse {
        // GRDB's `backup(to:)` runs on the queue itself, outside any transaction
        // by construction — so calling it from inside one re-enters and TRAPS,
        // killing the process rather than throwing. `checkpointTruncate` got this
        // guard when the boundary landed; this call and `closeDatabase` did not,
        // and review caught it. The deny-list on TX_BATCH covers only the WIRE
        // path; an in-process caller — which is precisely what the shared service
        // layer exists to enable — reaches here directly.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "backup")
        }
        try FileManager.default.createDirectory(at: Paths.backups, withIntermediateDirectories: true)

        // Timestamped filename (gmcc-YYYYMMDD-HHMMSS.db) with a -N suffix
        // loop as the sub-second collision guard (timestamps are
        // seconds-precision).
        let iso = Store.isoNow()  // 2026-08-21T20:45:18Z
        let parts = iso.dropLast().split(separator: "T", maxSplits: 1)
        let datePart = parts.first.map { $0.replacingOccurrences(of: "-", with: "") } ?? "unknown"
        let timePart = parts.count == 2 ? parts[1].replacingOccurrences(of: ":", with: "") : "000000"
        let stamp = "\(datePart)-\(timePart)"
        var destination = Paths.backups.appendingPathComponent("gmcc-\(stamp).db")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = Paths.backups.appendingPathComponent("gmcc-\(stamp)-\(attempt).db")
            attempt += 1
        }

        do {
            let destQueue = try DatabaseQueue(path: destination.path)
            try dbQueue.backup(to: destQueue)
            try destQueue.close()
        } catch {
            // A failed backup must not leave a partial db behind.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        let size =
            (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64)
            .flatMap(\.self) ?? 0

        if recordEvent {
            _ = try boundary { db in
                try self.appendEvent(
                    db,
                    kind: .backup,
                    payload: Store.jsonPayload([
                        "backup_path": destination.path, "size_bytes": Int(size),
                    ])
                )
            }
        }

        return BackupResponse(backupPath: destination.path, sizeBytes: size)
    }

    /// Check if the database has pending migrations.
    ///
    /// Returns true only when history exists AND it is behind this binary's migrations,
    /// the case where a migration rewrites rather than creates.
    /// - Returns: True if the database has pending migrations.
    /// - Throws: Database query or migration errors.
    func hasPendingMigrations() throws -> Bool {
        try boundaryRead { db in
            let applied = try Migrations.migrator.appliedMigrations(db)
            guard !applied.isEmpty else { return false }
            return try !Migrations.migrator.hasCompletedMigrations(db)
        }
    }

    /// Check if the database schema is ahead of this binary.
    ///
    /// Detects when a newer binary has modified the database, which GRDB cannot
    /// catch and would cause silent corruption if an older binary writes to it.
    /// - Returns: True if the database has been superseded by a newer binary.
    /// - Throws: Database query or schema errors.
    func hasBeenSuperseded() throws -> Bool {
        try boundaryRead { db in
            try Migrations.migrator.hasBeenSuperseded(db)
        }
    }

    /// Snapshot the database before migration.
    ///
    /// Uses the online backup path, not `cp`, to avoid tearing pages or missing rows
    /// in WAL mode.
    /// - Returns: The path to the backup file.
    /// - Throws: Backup or file system errors.
    @discardableResult
    func backupBeforeMigration() throws -> String {
        try backup(recordEvent: false).backupPath
    }
}
