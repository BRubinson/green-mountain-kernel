import Foundation
import GRDB

// CONTEXT_ENSURE / CONTEXT_GET — the promoted ensure chain (mirrors
// gmcc_session_startup.sh lazy creation) plus create-time-only kbite seeding
// (mirrors inherit_kbite). Bodies live in ContextRepository; these wrappers
// own the transaction.

extension Store {
    /// Upsert project → instance → session from repo identity, seeding kbite
    /// inheritance down the chain at CREATE time only. Idempotent; one
    /// transaction; returns all three uuids plus created flags.
    public func ensureContext(_ req: ContextEnsureRequest) throws -> ContextEnsureResponse {
        try dbQueue.write { db in try ContextRepository(db: db, core: core).ensureContext(req) }
    }

    /// Read-only resolution — never creates rows.
    public func getContext(_ req: ContextGetRequest) throws -> ContextGetResponse {
        try dbQueue.read { db in try ContextRepository(db: db, core: core).getContext(req) }
    }

    // MARK: - Cross-domain helper forwards (ensure chain shared with addFileChange)

    func ensureProject(_ db: Database, _ ctx: ProjectContext) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureProject(ctx)
    }

    func ensureInstance(
        _ db: Database, _ ctx: InstanceContext, projectUuid: String
    ) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureInstance(ctx, projectUuid: projectUuid)
    }

    func ensureSession(
        _ db: Database, _ ctx: SessionContext, instanceUuid: String
    ) throws -> (uuid: String, created: Bool) {
        try ContextRepository(db: db, core: core).ensureSession(ctx, instanceUuid: instanceUuid)
    }

    /// Upsert a kbite row by code, returning its uuid.
    func ensureKbite(_ db: Database, code: String) throws -> String {
        try ContextRepository(db: db, core: core).ensureKbite(code: code)
    }
}
