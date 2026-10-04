import Foundation
import GRDB

/// claude_session_binding data access: Claude Code's conversation uuid → gmcc
/// session (instance + branch) it was started in.
///
/// Runs INSIDE Store-owned transaction; holds no dbQueue, never self-transacts.
/// ONLY key payload-borne writes resolve through: hook payload carries
/// session_id and cwd; process ancestry cannot distinguish sibling subagents.
/// Table has two columns; missing ones are design (mid-session checkout leaves
/// binding on pinned session; staleness ACCEPTED, not detected).
struct ClaudeSessionBindingRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Pins a conversation to a session.
    ///
    /// Returns binding in force after (existing when pinned). Uses INSERT OR
    /// IGNORE, not read-then-branch: the UNIQUE index IS the pin-once rule.
    /// Re-run bounces off the schema. Base columns are spelled out because
    /// `insertBase` has no conflict clause.
    ///
    /// - Parameters:
    ///   - claudeSessionId: The Claude Code conversation UUID.
    ///   - sessionUuid: The gmcc session UUID to pin to.
    /// - Returns: The binding UUID.
    /// - Throws: `StoreError` on database failure or corrupt state.
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
            let uuid =
                try ClaudeSessionBindingRecord
                .filter(ClaudeSessionBindingRecord.Columns.claudeSessionId == claudeSessionId)
                .select(ClaudeSessionBindingRecord.Columns.uuid, as: String.self)
                .fetchOne(db)
        else {
            throw StoreError.corruptState(
                entity: "claude_session_binding",
                detail: "pin of \(claudeSessionId) left no row"
            )
        }
        return uuid
    }

    /// Resolves a conversation to its pinned session.
    ///
    /// The resolution step every payload-borne write starts from. nil means this
    /// conversation was never pinned — the caller decides whether that is
    /// somebody else's repo (silent) or dead capture in a known one (loud).
    ///
    /// - Parameter claudeSessionId: The Claude Code conversation UUID.
    /// - Returns: The pinned session UUID, or nil if not pinned.
    /// - Throws: `StoreError` on database failure.
    func resolveSession(claudeSessionId: String) throws -> String? {
        try ClaudeSessionBindingRecord
            .filter(ClaudeSessionBindingRecord.Columns.claudeSessionId == claudeSessionId)
            .select(ClaudeSessionBindingRecord.Columns.sessionUuid, as: String.self)
            .fetchOne(db)
    }
}
