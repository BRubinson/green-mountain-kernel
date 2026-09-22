// The one place identity-spine persistence types meet the wire DTOs.
//
// Every conversion is a `dto()` on the persistence side. Wire Rows stay free
// of GRDB conformances and of custom decoding.

import Foundation

extension SessionSummary {
    /// db → wire.
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
    /// db → wire. PromptRow is field-for-field identical to the record.
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
}

extension PromptSummary {
    /// db → wire. `reports` is the enrichment PROMPT_LIST attaches only when
    /// asked, so nil here keeps "not requested" distinct from "none exists".
    func dto(reports: PromptReportsStub?) -> PromptStub {
        PromptStub(
            uuid: prompt.uuid,
            sessionUuid: prompt.sessionUuid,
            seq: prompt.seq,
            code: prompt.code,
            name: prompt.name,
            status: prompt.status,
            version: prompt.version,
            gmfsRelativeStoragePath: prompt.gmfsRelativeStoragePath,
            reports: reports,
            createdAt: prompt.createdAt,
            updatedAt: prompt.updatedAt
        )
    }
}

extension PromptActivationRecord {
    /// db → wire.
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
