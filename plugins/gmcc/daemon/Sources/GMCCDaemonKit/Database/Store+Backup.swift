import Foundation
import GRDB

// BACKUP — SQLite Online Backup API via GRDB, into ~/gmcc/backups/.
// Required before real prompt content trusts the db.

extension Store {
    public func backup() throws -> BackupResponse {
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

        _ = try dbQueue.write { db in
            try self.appendEvent(
                db, kind: .backup,
                payload: Store.jsonPayload(["backup_path": destination.path, "size_bytes": Int(size)]))
        }

        return BackupResponse(backupPath: destination.path, sizeBytes: size)
    }
}
