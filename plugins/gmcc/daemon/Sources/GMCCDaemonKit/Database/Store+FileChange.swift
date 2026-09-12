import Foundation
import GRDB

// FILE_CHANGE_ADD / FILE_CHANGE_LIST — the original add_file_change
// capability plus the query side that replaces grepping changed_files: lists.
// Bodies live in FileChangeRepository; these wrappers own the transaction.

extension Store {
    public func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        do {
            return try dbQueue.write { db in try FileChangeRepository(db: db, core: core).add(req) }
        } catch StoreError.hookUnbound(let claudeSessionId, let booted) {
            // The ONE refusal that must leave a trace, and it needs its own
            // transaction to do it: the write that discovered the missing
            // binding rolled back, so an event appended inside it would have
            // rolled back with it — and a vanished event is exactly the
            // silence session-bound attribution exists to remove. A repo the
            // daemon does not know gets no event; a hook firing in somebody
            // else's repo is ordinary.
            if booted {
                try dbQueue.write { db in
                    try FileChangeRepository(db: db, core: core)
                        .recordUnbound(req, claudeSessionId: claudeSessionId)
                }
            }
            throw StoreError.hookUnbound(claudeSessionId: claudeSessionId, booted: booted)
        }
    }

    public func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try dbQueue.read { db in try FileChangeRepository(db: db, core: core).list(req) }
    }

    // MARK: - Cross-domain helper forward

    func ensureSessionFile(
        _ db: Database,
        sessionUuid: String,
        relativePath: String,
        changeKind: ChangeKind
    ) throws -> String {
        try FileChangeRepository(db: db, core: core).ensureSessionFile(
            sessionUuid: sessionUuid, relativePath: relativePath, changeKind: changeKind)
    }
}
