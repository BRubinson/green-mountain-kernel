import Foundation
import GMCCDaemonKit

/// BACKUP — SQLite Online Backup into ~/gmcc/backups/ (timestamped,
/// collision-guarded). Emits a BACKUP event.
enum BackupHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(BackupRequest.self, from: line)
        return try okResult(.backup, head, try store.backup())
    }
}
