import Foundation
import GRDB

/// Git-derived checked-out state reads (SESSION_RESOLVE /
/// INSTANCE_CURRENT_SESSION). Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct GitStateRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        guard let session = try session.fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        let instanceRoot = try String.fetchOne(db, sql: """
            SELECT i.absolute_file_system_path
            FROM session s JOIN instance i ON i.uuid = s.instance_uuid
            WHERE s.uuid = ?
            """, arguments: [req.sessionUuid]) ?? ""
        let (headState, currentCode, currentBranch) = Store.headSummary(repoRoot: instanceRoot)
        return SessionResolveResponse(
            session: session,
            checkedOut: currentCode != nil && currentCode == session.code,
            headState: headState,
            currentSessionCode: currentCode,
            currentBranch: currentBranch
        )
    }

    func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        guard let instanceRoot = try String.fetchOne(
            db, sql: "SELECT absolute_file_system_path FROM instance WHERE uuid = ?",
            arguments: [req.instanceUuid]
        ) else {
            throw StoreError.notFound(entity: "instance", key: req.instanceUuid)
        }
        let (headState, currentCode, currentBranch) = Store.headSummary(repoRoot: instanceRoot)
        var stub: SessionStub?
        if let code = currentCode {
            // Same column list + last_activity_at shape as SESSION_LIST.
            if let row = try SessionStubRecord.fetchOne(db, sql: """
                SELECT s.uuid, s.version, s.instance_uuid, s.code, s.name,
                       s.ckfs_relative_storage_path, s.created_at, s.updated_at,
                       MAX(
                           s.updated_at,
                           COALESCE((SELECT MAX(p.updated_at) FROM prompt p
                                     WHERE p.session_uuid = s.uuid), ''),
                           COALESCE((SELECT MAX(fc.created_at) FROM file_change fc
                                     WHERE fc.session_uuid = s.uuid), '')
                       ) AS last_activity_at
                FROM session s
                WHERE s.instance_uuid = ? AND s.code = ?
                """, arguments: [req.instanceUuid, code]) {
                stub = row.wireStub()
            }
        }
        return InstanceCurrentSessionResponse(
            session: stub, headState: headState, currentSessionCode: currentCode,
            currentBranch: currentBranch)
    }
}
