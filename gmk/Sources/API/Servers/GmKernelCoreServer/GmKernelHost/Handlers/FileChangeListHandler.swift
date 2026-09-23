import Foundation

/// FILE_CHANGE_LIST — query changes by session, prompt, or file with ranges
/// joined.
///
/// Replaces grepping changed_files: lists.
enum FileChangeListHandler {
    /// Handles the FILE_CHANGE_LIST wire request.
    ///
    /// Queries file changes by session, prompt, or file path with line ranges joined
    /// into a single response.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the change list response.
    /// - Throws: Errors from decoding or list operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(FileChangeListRequest.self, from: line)
        return try okResult(.fileChangeList, head, try store.listFileChanges(request))
    }
}
