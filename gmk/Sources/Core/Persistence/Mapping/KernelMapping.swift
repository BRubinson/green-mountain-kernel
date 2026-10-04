// db → wire for the kernel-domain records.
//
// This is the only place a persistence type and a wire DTO meet. Wire types
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension DaemonEventRecord {
    /// Converts a daemon event record to a wire notification.
    ///
    /// The `id` field is retained because it serves as the SUBSCRIBE replay
    /// cursor, not as an implementation detail. This is the only record that
    /// keeps the rowid as part of the wire type.
    ///
    /// - Returns: The wire event notification.
    func dto() -> EventNotification {
        EventNotification(
            id: id,
            kind: kind,
            createdAt: createdAt,
            subjectUuid: subjectUuid,
            payload: payload
        )
    }
}

extension TestRunRecord {
    /// Converts a test run record to a wire summary.
    ///
    /// Unknown run states are degraded to abandoned rather than crashing the
    /// read, since the column carries no CHECK constraint and a row written by
    /// newer bits must not poison a list.
    ///
    /// - Returns: The wire test run summary.
    func dto() -> TestRunSummary {
        TestRunSummary(
            uuid: uuid,
            projectUuid: projectUuid,
            runRoot: runRoot,
            suiteId: suiteId,
            // An unknown state on the wire is reported as abandoned rather than
            // crashing the read: the column carries no CHECK by design, so a
            // row written by newer bits must degrade rather than poison a list.
            state: TestRunState(rawValue: state) ?? .abandoned,
            doneKind: TestDoneKind(rawValue: doneKind) ?? .process,
            doneCondition: doneCondition,
            createdAt: createdAt,
            updatedAt: updatedAt,
            version: version,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            agentId: agentId,
            gitSha: gitSha,
            gitBranch: gitBranch,
            doneHint: doneHint,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: exitCode.map { Int32($0) },
            summary: summary
        )
    }
}
