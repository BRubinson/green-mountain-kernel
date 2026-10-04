import Foundation

/// FILE_CHANGE_ADD — ensures the project → instance → session chain, writes
/// session_file / file_change / file_change_range rows plus the FILE_CHANGE
/// daemon_event (one transaction).
///
/// Broadcast happens via the Store event sink — no handler-side notification
/// plumbing.
enum FileChangeHandler {
    /// Handles a file change addition request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The envelope header with metadata.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the added file change.
    /// - Throws: Server errors during processing or persistence.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(FileChangeAdd.self, from: line)
        return try okResult(.fileChangeAdd, head, try store.addFileChange(request))
    }
}
