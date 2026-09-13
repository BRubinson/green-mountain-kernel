import Foundation
import GRDB
import GmDaemonSdk

// BACKUP — SQLite Online Backup API via GRDB, into ~/gmfs/backups/.
// Required before real prompt content trusts the db.

extension Store {
    /// - Parameter recordEvent: append a `backup` row to the event log.
    ///   FALSE for the automatic pre-migration snapshot, and that is not a
    ///   nicety: at that moment the database is still on the OLD schema while
    ///   this binary's `appendEvent` writes the NEW one. Appending there would be
    ///   the one write in the whole backup path that could fail — or, worse,
    ///   succeed against a shape it was not written for — in the seconds before a
    ///   migration, which is precisely when the machine is least able to afford
    ///   it. The snapshot's value is the FILE; the audit row can wait for the
    ///   BACKUP verb, which runs on a migrated database.
    public func backup(recordEvent: Bool = true) throws -> BackupResponse {
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

        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64)
            .flatMap { $0 } ?? 0

        if recordEvent {
            _ = try boundary { db in
                try self.appendEvent(
                    db, kind: .backup,
                    payload: Store.jsonPayload([
                        "backup_path": destination.path, "size_bytes": Int(size),
                    ]))
            }
        }

        return BackupResponse(backupPath: destination.path, sizeBytes: size)
    }

    /// Is the database's migration ledger BEHIND this binary's?
    ///
    /// Two conditions, and the second is the one that matters. A db with
    /// migrations still to apply is only worth snapshotting if it already holds
    /// history — a brand-new file has nothing to lose, and backing one up on
    /// every fresh install would copy an empty database for no reason. So
    /// "pending" here means *there is existing history AND it is behind*, which
    /// is exactly the case where a migration rewrites rather than creates.
    public func hasPendingMigrations() throws -> Bool {
        try boundaryRead { db in
            let applied = try Migrations.migrator.appliedMigrations(db)
            guard !applied.isEmpty else { return false }
            return try !Migrations.migrator.hasCompletedMigrations(db)
        }
    }

    /// The automatic pre-migration snapshot.
    ///
    /// This is what REPLACED the sandbox dev loop. That snapshot runtime was the
    /// rehearsal surface for schema change, and deleting it — which is what
    /// dissolved the wrong-root hazard — took the rehearsal with it. The honest
    /// replacement is not a firmer instruction in a skill file; it is the kernel
    /// taking the copy itself, before the one operation in this system that does
    /// not append.
    ///
    /// Deliberately the SAME online-backup path as the `BACKUP` verb rather than
    /// a `cp`: a raw copy of a WAL-mode database under a live writer can capture
    /// a torn page or miss committed rows.
    @discardableResult
    public func backupBeforeMigration() throws -> String {
        try backup(recordEvent: false).backupPath
    }
}
