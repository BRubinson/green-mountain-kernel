import Foundation
import GRDB

// SESSION_GET / SESSION_UPDATE. Bodies live in SessionRepository; these
// wrappers own the transaction. The liveness statics stay on Store.

extension Store {
    public func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        try dbQueue.read { db in try SessionRepository(db: db, core: core).getSession(req) }
    }

    public func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        try dbQueue.write { db in try SessionRepository(db: db, core: core).updateSession(req) }
    }

    // MARK: - Liveness statics

    /// Liveness by key shape: "claude:<pid>:<starttime>" keys are checked
    /// against the process table; unknown shapes are presumed alive (we
    /// cannot check what we cannot parse, and false eviction is the worse
    /// failure).
    static func clientKeyLooksAlive(_ key: String) -> Bool {
        let parts = key.split(separator: ":")
        guard parts.count == 3, parts[0] == "claude",
              let pid = Int32(parts[1]), let start = Int64(parts[2]) else { return true }
        return Store.processAlive(pid: pid, startTimeSeconds: start)
    }

    static func processAlive(pid: Int32, startTimeSeconds: Int64) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              size > 0, info.kp_proc.p_pid == pid else {
            return false
        }
        return Int64(info.kp_proc.p_starttime.tv_sec) == startTimeSeconds
    }

    // MARK: - Cross-domain helper forwards

    func fetchSessionRow(_ db: Database, uuid: String) throws -> SessionRow? {
        try SessionRepository(db: db, core: core).fetchRow(uuid: uuid)
    }

    func claimActivation(
        _ db: Database, sessionUuid: String, promptUuid: String, clientKey: String
    ) throws {
        try SessionRepository(db: db, core: core).claimActivation(
            sessionUuid: sessionUuid, promptUuid: promptUuid, clientKey: clientKey)
    }

    func evictDeadActivations(_ db: Database, sessionUuid: String) throws {
        try SessionRepository(db: db, core: core).evictDeadActivations(sessionUuid: sessionUuid)
    }

    func fetchActivations(_ db: Database, sessionUuid: String) throws -> [PromptActivationRow] {
        try SessionRepository(db: db, core: core).fetchActivations(sessionUuid: sessionUuid)
    }

    func resolveActivePrompt(
        _ db: Database, sessionUuid: String, clientKey: String?
    ) throws -> String? {
        try SessionRepository(db: db, core: core).resolveActivePrompt(
            sessionUuid: sessionUuid, clientKey: clientKey)
    }

    func fetchPromptStubs(
        _ db: Database, sessionUuid: String?, withReports: Bool = false
    ) throws -> [PromptStub] {
        try SessionRepository(db: db, core: core).fetchPromptStubs(
            sessionUuid: sessionUuid, withReports: withReports)
    }

    func changeSummary(
        _ db: Database,
        where condition: String,
        arguments: StatementArguments
    ) throws -> ChangeSummary {
        try SessionRepository(db: db, core: core).changeSummary(
            where: condition, arguments: arguments)
    }

    func promptChangeSummaries(_ db: Database, sessionUuid: String) throws -> [PromptChangeSummary] {
        try SessionRepository(db: db, core: core).promptChangeSummaries(sessionUuid: sessionUuid)
    }
}
