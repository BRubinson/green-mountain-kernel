import Foundation
import GRDB

// FILE_CHANGE_ADD / FILE_CHANGE_LIST — the original add_file_change
// capability plus the query side that replaces grepping changed_files: lists.
// Bodies live in FileChangeRepository; these wrappers own the transaction.

extension Store {
    /// Records a file change event from a source agent or hook.
    ///
    /// - Parameter req: The change request with session, file path, and change kind.
    /// - Returns: The created file change row.
    /// - Throws: `StoreError.hookUnbound` when the hook is not bound to a repo.
    func addFileChange(_ req: FileChangeAdd) throws -> FileChangeAddResponse {
        do {
            return try boundary { db in try FileChangeRepository(db: db, core: core).add(req) }
        } catch StoreError.hookUnbound(let claudeSessionId, let booted) {
            // The ONE refusal that must leave a trace, and it needs its own
            // transaction to do it: the write that discovered the missing
            // binding rolled back, so an event appended inside it would have
            // rolled back with it — and a vanished event is exactly the
            // silence session-bound attribution exists to remove. A repo the
            // daemon does not know gets no event; a hook firing in somebody
            // else's repo is ordinary.
            if booted {
                try boundary { db in
                    try FileChangeRepository(db: db, core: core)
                        .recordUnbound(req, claudeSessionId: claudeSessionId)
                }
            }
            throw StoreError.hookUnbound(claudeSessionId: claudeSessionId, booted: booted)
        }
    }

    /// Fetches file changes for a session, grouped by file and ordered by timestamp.
    ///
    /// - Parameter req: The list request with session uuid and optional filter.
    /// - Returns: The file changes grouped by file path.
    /// - Throws: Database errors.
    func listFileChanges(_ req: FileChangeListRequest) throws -> FileChangeListResponse {
        try boundaryRead { db in try FileChangeRepository(db: db, core: core).list(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Creates or returns a session-scoped file change for path discovery.
    ///
    /// - Parameters:
    ///   - db: The database handle; must be within a transaction.
    ///   - sessionUuid: The session uuid.
    ///   - relativePath: The file path relative to the repo root.
    ///   - changeKind: The type of change (add, modify, delete, etc.).
    /// - Returns: The file change uuid.
    /// - Throws: Database errors.
    func ensureSessionFile(
        _ db: Database,
        sessionUuid: String,
        relativePath: String,
        changeKind: ChangeKind
    ) throws -> String {
        try FileChangeRepository(db: db, core: core)
            .ensureSessionFile(
                sessionUuid: sessionUuid,
                relativePath: relativePath,
                changeKind: changeKind
            )
    }
}
