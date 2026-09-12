import Foundation
import GMCCDaemonKit

/// FILE_CHANGE_LIST — query changes by session, prompt, or file with ranges
/// joined. Replaces grepping changed_files: lists.
enum FileChangeListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(FileChangeListRequest.self, from: line)
        return try okResult(.fileChangeList, head, try store.listFileChanges(request))
    }
}
