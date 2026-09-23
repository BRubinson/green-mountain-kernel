// The one place identity-spine persistence types meet the wire DTOs.
//
// Every conversion is a `dto()` on the persistence side. Wire Rows stay free
// of GRDB conformances and of custom decoding.

import Foundation

extension ProjectRecord {
    /// db → wire.
    ///
    /// - Returns: The wire projection of this project record.
    func dto() -> ProjectRow {
        ProjectRow(
            uuid: uuid,
            version: version,
            gitRepoName: gitRepoName,
            code: code,
            name: name,
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            primaryProjectBranch: primaryProjectBranch
        )
    }
}

extension InstanceRecord {
    /// db → wire.
    ///
    /// - Returns: The wire projection of this instance record.
    func dto() -> InstanceRow {
        InstanceRow(
            uuid: uuid,
            version: version,
            projectUuid: projectUuid,
            code: code,
            name: name,
            absoluteFileSystemPath: absoluteFileSystemPath,
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension SessionSummary {
    /// db → wire.
    ///
    /// - Returns: The wire stub of this session summary.
    func dto() -> SessionStub {
        SessionStub(
            uuid: session.uuid,
            version: session.version,
            instanceUuid: session.instanceUuid,
            code: session.code,
            name: session.name,
            gmfsRelativeStoragePath: session.gmfsRelativeStoragePath,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            lastActivityAt: lastActivityAt
        )
    }
}

extension SessionWithActivations {
    /// db → wire.
    ///
    /// - Returns: The wire projection of this session with activations.
    func dto() -> SessionRow {
        SessionRow(
            uuid: session.uuid,
            version: session.version,
            code: session.code,
            name: session.name,
            backstory: session.backstory,
            goal: session.goal,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            activations: activations.map { $0.dto() }
        )
    }
}

extension PromptRecord {
    /// db → wire.
    ///
    /// PromptRow is field-for-field identical to the record.
    ///
    /// - Returns: The wire projection of this prompt record.
    func dto() -> PromptRow {
        PromptRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            seq: seq,
            code: code,
            name: name,
            backstory: backstory,
            goal: goal,
            detail: detail,
            command: command,
            status: status,
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Wire stub of this prompt with optional enriched reports.
    ///
    /// `reports` is the enrichment PROMPT_LIST attaches only when asked, so
    /// nil here keeps "not requested" distinct from "none exists".
    ///
    /// - Parameter reports: The optional report enrichment.
    /// - Returns: The wire stub of this prompt.
    func dto(reports: PromptReportsStub?) -> PromptStub {
        PromptStub(
            uuid: uuid,
            sessionUuid: sessionUuid,
            seq: seq,
            code: code,
            name: name,
            status: status,
            version: version,
            gmfsRelativeStoragePath: gmfsRelativeStoragePath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            reports: reports
        )
    }
}

extension ClarificationReport {
    /// db → wire.
    ///
    /// - Returns: The wire stub of this clarification report.
    func dto() -> ClarificationReportStub {
        ClarificationReportStub(
            summaryUuid: summary.uuid,
            version: summary.version,
            status: summary.status,
            questionCount: questionCount,
            openQuestionCount: openQuestionCount,
            noteCount: noteCount,
            carePackageReady: carePackageReady
        )
    }
}

extension ArchitectureReport {
    /// db → wire.
    ///
    /// - Returns: The wire stub of this architecture report.
    func dto() -> ArchitectureReportStub {
        ArchitectureReportStub(
            summaryUuid: summary.uuid,
            version: summary.version,
            status: summary.status,
            persistenceChangeCount: persistenceChangeCount,
            generalChangeCount: generalChangeCount
        )
    }
}

extension ExplorationReport {
    /// db → wire.
    ///
    /// The identity is the pivot's representative row, never one agent's own
    /// summary.
    ///
    /// - Returns: The wire stub of this exploration report.
    func dto() -> ExplorationReportStub {
        ExplorationReportStub(
            summaryUuid: repUuid,
            version: repVersion,
            status: repStatus,
            keyFileCount: keyFileCount,
            findingCount: findingCount,
            sub100FindingCount: sub100FindingCount,
            unrankedFindingCount: unrankedFindingCount
        )
    }
}

extension ReviewReport {
    /// db → wire.
    ///
    /// - Returns: The wire stub of this review report.
    func dto() -> ReviewReportStub {
        ReviewReportStub(
            summaryUuid: summary.uuid,
            version: summary.version,
            status: summary.status,
            verdict: summary.verdict,
            findingCount: findingCount,
            sub100FindingCount: sub100FindingCount,
            unrankedFindingCount: unrankedFindingCount,
            openFindingCount: openFindingCount
        )
    }
}

extension ChangeRollup {
    /// db → wire.
    ///
    /// - Returns: The wire summary of this change rollup.
    func dto() -> ChangeSummary {
        ChangeSummary(
            changeCount: changeCount,
            distinctFiles: distinctFiles,
            totalLineSpan: totalLineSpan
        )
    }
}

extension PromptChangeRollup {
    /// db → wire.
    ///
    /// - Returns: The wire summary of this prompt change rollup.
    func dto() -> PromptChangeSummary {
        PromptChangeSummary(
            promptUuid: promptUuid,
            summary: ChangeSummary(
                changeCount: changeCount,
                distinctFiles: distinctFiles,
                totalLineSpan: totalLineSpan
            )
        )
    }
}

extension PromptActivationRecord {
    /// db → wire.
    ///
    /// - Returns: The wire projection of this prompt activation record.
    func dto() -> PromptActivationRow {
        PromptActivationRow(
            uuid: uuid,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            clientKey: clientKey,
            createdAt: createdAt
        )
    }
}
