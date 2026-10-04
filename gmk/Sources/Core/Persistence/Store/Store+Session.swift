import Foundation
import GRDB

// SESSION_GET / SESSION_UPDATE. Bodies live in SessionRepository; these
// wrappers own the transaction. The liveness statics stay on Store.

extension Store {
    /// Fetches the current session data.
    ///
    /// - Parameter req: The session get request.
    /// - Returns: The session data response.
    /// - Throws: Any error from the repository.
    func getSession(_ req: SessionGetRequest) throws -> SessionGetResponse {
        try boundaryRead { db in try SessionRepository(db: db, core: core).getSession(req) }
    }

    /// Updates the session with the given request.
    ///
    /// - Parameter req: The session update request.
    /// - Returns: The updated session row.
    /// - Throws: Any error from the repository.
    func updateSession(_ req: SessionUpdateRequest) throws -> SessionRow {
        try boundary { db in try SessionRepository(db: db, core: core).updateSession(req) }
    }

    // MARK: - Liveness statics

    /// Checks whether a client with the given key shape is likely still running.
    ///
    /// Keys matching "claude:<pid>:<starttime>" are checked against the process table.
    /// Unknown shapes are presumed alive since false eviction is worse than keeping a
    /// dead client's activation.
    ///
    /// - Parameter key: The client key, typically "claude:<pid>:<starttime>".
    /// - Returns: True if the process appears to be running.
    static func clientKeyLooksAlive(_ key: String) -> Bool {
        let parts = key.split(separator: ":")
        guard parts.count == 3, parts[0] == "claude",
            let pid = Int32(parts[1]), let start = Int64(parts[2])
        else { return true }
        return Store.processAlive(pid: pid, startTimeSeconds: start)
    }

    /// Checks whether the process with the given ID and start time is still running.
    ///
    /// - Parameters:
    ///   - pid: The process ID to check.
    ///   - startTimeSeconds: The process start time in seconds since epoch.
    /// - Returns: True if the process exists and started at the given time.
    static func processAlive(pid: Int32, startTimeSeconds: Int64) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
            size > 0, info.kp_proc.p_pid == pid
        else {
            return false
        }
        return Int64(info.kp_proc.p_starttime.tv_sec) == startTimeSeconds
    }

    // MARK: - Cross-domain helper forwards

    /// Fetches a session row by UUID.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The session UUID to fetch.
    /// - Returns: The session row, or nil if not found.
    /// - Throws: Any database error.
    func fetchSessionRow(_ db: Database, uuid: String) throws -> SessionRow? {
        try SessionRepository(db: db, core: core).fetchRow(uuid: uuid)
    }

    /// Records a prompt activation claim for the given client.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID.
    ///   - promptUuid: The prompt UUID being activated.
    ///   - clientKey: The client key claiming the activation.
    /// - Throws: Any database error.
    func claimActivation(
        _ db: Database,
        sessionUuid: String,
        promptUuid: String,
        clientKey: String
    ) throws {
        try SessionRepository(db: db, core: core)
            .claimActivation(
                sessionUuid: sessionUuid,
                promptUuid: promptUuid,
                clientKey: clientKey
            )
    }

    /// Removes activations for dead client processes.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID whose activations to clean.
    /// - Throws: Any database error.
    func evictDeadActivations(_ db: Database, sessionUuid: String) throws {
        try SessionRepository(db: db, core: core).evictDeadActivations(sessionUuid: sessionUuid)
    }

    /// Fetches the prompt activations for a session.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID whose activations to fetch.
    /// - Returns: The activation rows for the session.
    /// - Throws: Any database error.
    func fetchActivations(_ db: Database, sessionUuid: String) throws -> [PromptActivationRow] {
        try SessionRepository(db: db, core: core).fetchActivations(sessionUuid: sessionUuid)
    }

    /// Resolves the currently active prompt UUID for a session.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID.
    ///   - clientKey: The client key requesting the active prompt; nil to ignore client.
    /// - Returns: The active prompt UUID, or nil if none is active.
    /// - Throws: Any database error.
    func resolveActivePrompt(
        _ db: Database,
        sessionUuid: String,
        clientKey: String?
    ) throws -> String? {
        try SessionRepository(db: db, core: core)
            .resolveActivePrompt(
                sessionUuid: sessionUuid,
                clientKey: clientKey
            )
    }

    /// Fetches prompt stubs, optionally including their reports.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID; nil to fetch across all sessions.
    ///   - withReports: Whether to include prompt reports; defaults to false.
    /// - Returns: The prompt stubs.
    /// - Throws: Any database error.
    func fetchPromptStubs(
        _ db: Database,
        sessionUuid: String?,
        withReports: Bool = false
    ) throws -> [PromptStub] {
        try SessionRepository(db: db, core: core)
            .fetchPromptStubs(
                sessionUuid: sessionUuid,
                withReports: withReports
            )
    }

    /// Summarizes changes to a session.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID.
    /// - Returns: A summary of changes to the session.
    /// - Throws: Any database error.
    func changeSummary(_ db: Database, sessionUuid: String) throws -> ChangeSummary {
        try SessionRepository(db: db, core: core).changeSummary(sessionUuid: sessionUuid)
    }

    /// Summarizes changes to a prompt.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - promptUuid: The prompt UUID.
    /// - Returns: A summary of changes to the prompt.
    /// - Throws: Any database error.
    func changeSummary(_ db: Database, promptUuid: String) throws -> ChangeSummary {
        try SessionRepository(db: db, core: core).changeSummary(promptUuid: promptUuid)
    }

    /// Summarizes changes to each prompt in a session.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - sessionUuid: The session UUID.
    /// - Returns: A change summary for each prompt in the session.
    /// - Throws: Any database error.
    func promptChangeSummaries(_ db: Database, sessionUuid: String) throws -> [PromptChangeSummary] {
        try SessionRepository(db: db, core: core).promptChangeSummaries(sessionUuid: sessionUuid)
    }
}
