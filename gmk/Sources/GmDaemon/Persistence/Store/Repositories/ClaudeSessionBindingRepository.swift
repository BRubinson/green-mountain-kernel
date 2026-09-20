import Foundation
import GRDB
import GmDaemonSdk

/// claude_session_binding data access: Claude Code's conversation uuid → the
/// gmcc session (instance + branch) it was started in. Runs INSIDE a
/// Store-owned transaction; holds no dbQueue and never self-transacts.
/// This is the ONLY key a payload-borne write resolves through: a hook payload
/// carries a session_id and a cwd, and process ancestry cannot tell one sibling
/// subagent from another. The table has exactly two columns, and the missing
/// ones are the design — a mid-session checkout leaves the binding on the
/// session it was pinned to, and that staleness is ACCEPTED, not detected.
struct ClaudeSessionBindingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Pin a conversation to a session, once. Returns the binding in force
    /// afterwards, which is the existing one when already pinned.
    ///
    /// INSERT OR IGNORE, not a read-then-branch: the UNIQUE index on
    /// claude_session_id IS the pin-once rule, so a re-run bounces off the
    /// schema rather than a condition a caller can forget. The base columns are
    /// spelled out because `insertBase` has no conflict clause, and teaching it
    /// one would put OR IGNORE within reach of every table.
    @discardableResult
    func pin(claudeSessionId: String, sessionUuid: String) throws -> String {
        let now = Store.isoNow()
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO claude_session_binding
                    (uuid, version, created_at, updated_at, claude_session_id, session_uuid)
                VALUES (?, 0, ?, ?, ?, ?)
                """,
            arguments: [StoreCore.newUuid(), now, now, claudeSessionId, sessionUuid]
        )
        guard
            let uuid = try String.fetchOne(
                db,
                sql: "SELECT uuid FROM claude_session_binding WHERE claude_session_id = ?",
                arguments: [claudeSessionId]
            )
        else {
            throw StoreError.corruptState(
                entity: "claude_session_binding",
                detail: "pin of \(claudeSessionId) left no row"
            )
        }
        return uuid
    }

    /// The resolution step every payload-borne write starts from. nil means
    /// this conversation was never pinned — the caller decides whether that is
    /// somebody else's repo (silent) or dead capture in a known one (loud).
    func resolveSession(claudeSessionId: String) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT session_uuid FROM claude_session_binding WHERE claude_session_id = ?",
            arguments: [claudeSessionId]
        )
    }
}
