import Foundation
import GMCCDaemonKit

/// FILE_CHANGE_ADD — ensures the project → instance → session chain, writes
/// session_file / file_change / file_change_range rows plus the FILE_CHANGE
/// daemon_event (one transaction). Broadcast happens via the Store event
/// sink — no handler-side notification plumbing.
enum FileChangeHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(FileChangeAdd.self, from: line)
        return try okResult(.fileChangeAdd, head, try store.addFileChange(request))
    }
}
