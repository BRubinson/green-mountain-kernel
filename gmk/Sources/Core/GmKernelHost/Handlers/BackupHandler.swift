import Foundation

/// BACKUP — SQLite Online Backup into ~/gmfs/backups/ (timestamped,
/// collision-guarded).
///
/// Emits a BACKUP event.
enum BackupHandler {
    /// Handles a backup request and returns the result.
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header.
    ///   - store: The database store to back up.
    /// - Returns: The handler result containing backup status.
    /// - Throws: Any error during backup.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(BackupRequest.self, from: line)
        return try okResult(.backup, head, try store.backup())
    }
}
