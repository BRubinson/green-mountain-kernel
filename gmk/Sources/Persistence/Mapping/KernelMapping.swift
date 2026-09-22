// db → wire for the kernel-domain records.
//
// This is the only place a persistence type and a wire DTO meet. Wire types
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension DaemonEventRecord {
    /// The wire type is `EventNotification`, and `id` is genuinely part of it:
    /// this is the one record that keeps the rowid, because it is the SUBSCRIBE
    /// replay cursor rather than an implementation detail.
    func dto() -> EventNotification {
        EventNotification(
            id: id,
            kind: kind,
            subjectUuid: subjectUuid,
            payload: payload,
            createdAt: createdAt
        )
    }
}

extension TestRunRecord {
    func dto() -> TestRunSummary {
        TestRunSummary(
            uuid: uuid,
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            agentId: agentId,
            runRoot: runRoot,
            suiteId: suiteId,
            gitSha: gitSha,
            gitBranch: gitBranch,
            // An unknown state on the wire is reported as abandoned rather than
            // crashing the read: the column carries no CHECK by design, so a
            // row written by newer bits must degrade rather than poison a list.
            state: TestRunState(rawValue: state) ?? .abandoned,
            doneKind: TestDoneKind(rawValue: doneKind) ?? .process,
            doneCondition: doneCondition,
            doneHint: doneHint,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exitCode: exitCode.map { Int32($0) },
            summary: summary,
            createdAt: createdAt,
            updatedAt: updatedAt,
            version: version
        )
    }
}
