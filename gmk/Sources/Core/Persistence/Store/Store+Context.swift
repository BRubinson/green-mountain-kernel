import Foundation
import GRDB

// CONTEXT_ENSURE / CONTEXT_GET — the promoted ensure chain (mirrors
// gm_session_startup.sh lazy creation) plus create-time-only kbite seeding
// (mirrors inherit_kbite). Bodies live in ContextRepository; these wrappers
// own the transaction.

extension Store {
    /// Upserts the project-instance-session chain and seeds kbite inheritance.
    ///
    /// One transaction returning all three uuids plus created flags. Kbite
    /// inheritance is seeded at CREATE time only.
    /// - Parameter req: The context ensure request with project, instance, and
    ///   session contexts.
    /// - Returns: The ensure response with uuids and created flags.
    /// - Throws: Any error from the repository.
    func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        try boundary { db in try ContextRepository(db: db, core: core).ensureContext(req) }
    }

    /// Reads and resolves the context chain without creating rows.
    /// - Parameter req: The context get request.
    /// - Returns: The get response with resolved context.
    /// - Throws: Any error from the repository.
    func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        try boundaryRead { db in try ContextRepository(db: db, core: core).getContext(req) }
    }

    // MARK: - Cross-domain helper forwards (ensure chain shared with addFileChange)

    /// Upserts a project and returns its uuid and created flag.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - ctx: The project context with name and identity.
    /// - Returns: A tuple with the project uuid and created flag.
    /// - Throws: Any error from the repository.
    func ensureProject(_ db: Database, _ ctx: ProjectContext) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureProject(ctx)
    }

    /// Upserts an instance and returns its uuid and created flag.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - ctx: The instance context with name and identity.
    ///   - projectUuid: The parent project uuid.
    /// - Returns: A tuple with the instance uuid and created flag.
    /// - Throws: Any error from the repository.
    func ensureInstance(
        _ db: Database,
        _ ctx: InstanceContext,
        projectUuid: String
    ) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureInstance(ctx, projectUuid: projectUuid)
    }

    /// Upserts a session and returns its uuid and created flag.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - ctx: The session context with name and identity.
    ///   - instanceUuid: The parent instance uuid.
    /// - Returns: A tuple with the session uuid and created flag.
    /// - Throws: Any error from the repository.
    func ensureSession(
        _ db: Database,
        _ ctx: SessionContext,
        instanceUuid: String
    ) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureSession(ctx, instanceUuid: instanceUuid)
    }

    /// Upserts a kbite row by code and returns its uuid.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - code: The kbite code.
    /// - Returns: The kbite row uuid.
    /// - Throws: Any error from the repository.
    func ensureKbite(_ db: Database, code: String) throws -> String {
        try ContextRepository(db: db, core: core).ensureKbite(code: code)
    }
}
