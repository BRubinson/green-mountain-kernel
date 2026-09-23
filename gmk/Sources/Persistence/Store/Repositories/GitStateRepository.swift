import Foundation
import GRDB

/// Git-derived checked-out state reads (SESSION_RESOLVE /
/// INSTANCE_CURRENT_SESSION).
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts.
struct GitStateRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// Resolves a session's checked-out state in the git repository.
    ///
    /// - Parameter req: The session resolve request with session uuid.
    /// - Returns: The session with git state information.
    /// - Throws: `StoreError` when the session does not exist.
    func sessionResolve(_ req: SessionResolveRequest) throws -> SessionResolveResponse {
        guard let session = try session.fetchRow(uuid: req.sessionUuid) else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        let instanceRoot =
            try InstanceRecord
            .joining(required: InstanceRecord.sessions.withUuid(req.sessionUuid))
            .select(InstanceRecord.Columns.absoluteFileSystemPath, as: String.self)
            .fetchOne(db) ?? ""
        let (headState, currentCode, currentBranch) = Store.headSummary(repoRoot: instanceRoot)
        return SessionResolveResponse(
            session: session,
            checkedOut: currentCode != nil && currentCode == session.code,
            headState: headState,
            currentSessionCode: currentCode,
            currentBranch: currentBranch
        )
    }

    /// Resolves the currently checked-out session for an instance.
    ///
    /// - Parameter req: The instance current session request with instance uuid.
    /// - Returns: The session stub if found, with git state information.
    /// - Throws: `StoreError` when the instance does not exist.
    func instanceCurrentSession(
        _ req: InstanceCurrentSessionRequest
    ) throws -> InstanceCurrentSessionResponse {
        guard
            let instanceRoot =
                try InstanceRecord
                .all()
                .withUuid(req.instanceUuid)
                .select(InstanceRecord.Columns.absoluteFileSystemPath, as: String.self)
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "instance", key: req.instanceUuid)
        }
        let (headState, currentCode, currentBranch) = Store.headSummary(repoRoot: instanceRoot)
        var stub: SessionStub?
        if let code = currentCode {
            stub =
                try SessionSummary.request()
                .filter(SessionRecord.Columns.instanceUuid == req.instanceUuid)
                .filter(SessionRecord.Columns.code == code)
                .fetchOne(db)?
                .dto()
        }
        return InstanceCurrentSessionResponse(
            session: stub,
            headState: headState,
            currentSessionCode: currentCode,
            currentBranch: currentBranch
        )
    }
}
