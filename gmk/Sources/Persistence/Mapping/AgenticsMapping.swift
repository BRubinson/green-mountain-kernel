// db → wire for the agentics composites and their ref children.
//
// This is the only place a persistence type and a wire Row meet. Wire Rows
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension AgentBriefingWithRefs {
    func dto() -> AgentBriefingRow {
        AgentBriefingRow(
            uuid: agentBriefing.uuid,
            version: agentBriefing.version,
            sessionUuid: agentBriefing.sessionUuid,
            promptUuid: agentBriefing.promptUuid,
            briefingForStep: agentBriefing.briefingForStep,
            status: agentBriefing.status,
            agentId: agentBriefing.agentId,
            dopeScopeUuid: agentBriefing.dopeScopeUuid,
            dopeScopeRevision: agentBriefing.dopeScopeRevision,
            dopeRefs: dopeRefs.map { $0.dto() },
            kbiteRefs: kbiteRefs.map { $0.dto() },
            fileChangeRefs: fileChangeRefs.map { $0.dto() },
            createdAt: agentBriefing.createdAt,
            updatedAt: agentBriefing.updatedAt
        )
    }
}

extension AgentBriefingDopePersistenceRecord {
    func dto() -> AgentBriefingDopeRefRow {
        AgentBriefingDopeRefRow(uuid: uuid, dopeCode: dopeCode, brief: brief, seq: Int(seq))
    }
}

extension AgentBriefingDopeKbiteRecord {
    func dto() -> AgentBriefingKbiteRefRow {
        AgentBriefingKbiteRefRow(
            uuid: uuid,
            kbiteResourceFileUuid: kbiteResourceFileUuid,
            brief: brief,
            seq: Int(seq)
        )
    }
}

extension AgentSessionFileChangeRecord {
    func dto() -> AgentBriefingFileChangeRefRow {
        AgentBriefingFileChangeRefRow(uuid: uuid, fileChangeUuid: fileChangeUuid, seq: Int(seq))
    }
}

extension ClarificationQuestionWithOptions {
    /// The selections are a junction read the caller batches across questions,
    /// so they arrive labelled and un-defaulted rather than as a second query
    /// hidden behind a default.
    func dto(selectedOptionUuids: [String]) -> ClarificationQuestionRow {
        ClarificationQuestionRow(
            uuid: questionRow.uuid,
            version: questionRow.version,
            clarificationSummaryUuid: questionRow.clarificationSummaryUuid,
            seq: questionRow.seq,
            question: questionRow.question,
            status: questionRow.status,
            answerText: questionRow.answerText,
            agentId: questionRow.agentId,
            agentName: questionRow.agentName,
            options: options.map { $0.dto() },
            selectedOptionUuids: selectedOptionUuids
        )
    }
}

extension UserClarificationOptionRecord {
    func dto() -> ClarificationOptionRow {
        ClarificationOptionRow(uuid: uuid, seq: seq, body: body)
    }
}

extension ArchPersistenceChangeWithFields {
    /// `implementation` is computed against the file-change trail, not read
    /// from this table, so it stays labelled and un-defaulted: a default would
    /// let a caller silently drop it.
    func dto(implementation: ChangeImplementationState) -> ArchPersistenceChangeRow {
        ArchPersistenceChangeRow(
            uuid: change.uuid,
            seq: change.seq,
            className: change.className,
            filePath: change.filePath,
            reasonBrief: change.reasonBrief,
            changeKind: change.changeKind,
            dopeRef: change.dopeRef,
            fields: fields.map { $0.dto() },
            implementation: implementation
        )
    }
}

extension ArchitecturePersistenceFieldChangeRecord {
    func dto() -> ArchPersistenceFieldChangeRow {
        ArchPersistenceFieldChangeRow(
            uuid: uuid,
            seq: seq,
            fieldName: fieldName,
            changeReason: changeReason,
            changePurpose: changePurpose,
            dataType: dataType,
            nullable: nullable,
            isForeignKey: isForeignKey,
            fkTarget: fkTarget,
            isIndexed: isIndexed,
            changeKind: changeKind,
            renamedFrom: renamedFrom,
            dopePropertyRef: dopePropertyRef
        )
    }
}

extension ArchitectureGeneralChangeRecord {
    /// See the persistence twin above for why `implementation` is labelled and
    /// un-defaulted.
    func dto(implementation: ChangeImplementationState) -> ArchGeneralChangeRow {
        ArchGeneralChangeRow(
            uuid: uuid,
            seq: seq,
            filePath: filePath,
            className: className,
            reasonBrief: reasonBrief,
            changeDepth: changeDepth,
            changeCode: changeCode,
            implementation: implementation
        )
    }
}

extension ExplorationSummaryRecord {
    func dto() -> ExplorationSummaryRow {
        ExplorationSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            agentType: agentType,
            agentId: agentId,
            status: status,
            overview: overview,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension ExplorationFindingRecord {
    /// findingRating narrows Int64 (the column type) to the wire's Int,
    /// explicitly and non-truncating.
    func dto() -> ExplorationFindingRow {
        ExplorationFindingRow(
            uuid: uuid,
            version: version,
            explorationSummaryUuid: explorationSummaryUuid,
            kind: kind,
            title: title,
            body: body,
            filePath: filePath,
            agentName: agentName,
            agentId: agentId,
            findingRating: findingRating.map(Int.init)
        )
    }
}

extension ReviewSummaryRecord {
    func dto() -> ReviewSummaryRow {
        ReviewSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            verdict: verdict,
            overview: overview,
            agentId: agentId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension ReviewFindingRecord {
    /// lineStart/lineEnd/findingRating narrow Int64 (the column type) to the
    /// wire's Int, explicitly and non-truncating.
    func dto() -> ReviewFindingRow {
        ReviewFindingRow(
            uuid: uuid,
            version: version,
            reviewSummaryUuid: reviewSummaryUuid,
            kind: kind,
            title: title,
            body: body,
            filePath: filePath,
            lineStart: lineStart.map(Int.init),
            lineEnd: lineEnd.map(Int.init),
            agentName: agentName,
            findingRating: findingRating.map(Int.init),
            status: status
        )
    }
}

extension FileChangeWithRanges {
    func dto() -> FileChangeRow {
        FileChangeRow(
            uuid: fileChange.uuid,
            sessionUuid: fileChange.sessionUuid,
            promptUuid: fileChange.promptUuid,
            relativePath: relativePath,
            changeKind: fileChange.changeKind,
            agentId: fileChange.agentId,
            agentName: fileChange.agentName,
            workflowPhase: fileChange.workflowPhase,
            origin: fileChange.origin,
            claudeSessionId: fileChange.claudeSessionId,
            claudeTurnId: fileChange.claudeTurnId,
            toolUseId: fileChange.toolUseId,
            toolName: fileChange.toolName,
            agentType: fileChange.agentType,
            permissionMode: fileChange.permissionMode,
            durationMs: fileChange.durationMs.map(Int.init),
            transcriptPath: fileChange.transcriptPath,
            agentRegistrationUuid: fileChange.agentRegistrationUuid,
            createdAt: fileChange.createdAt,
            ranges: ranges.map { $0.dto() }
        )
    }
}

extension FileChangeRangeRecord {
    func dto() -> ChangeRangeRow {
        ChangeRangeRow(lineStart: Int(lineStart), lineEnd: Int(lineEnd))
    }
}

extension CarePackageWithRefs {
    func dto() -> CarePackageRow {
        CarePackageRow(
            uuid: carePackage.uuid,
            version: carePackage.version,
            clarificationSummaryUuid: carePackage.clarificationSummaryUuid,
            clarifiedIntent: carePackage.clarifiedIntent,
            status: carePackage.status,
            dopeScopeUuid: carePackage.dopeScopeUuid,
            dopeScopeRevision: carePackage.dopeScopeRevision,
            dopeRefs: dopeRefs.map { $0.dto() },
            kbiteRefs: kbiteRefs.map { $0.dto() },
            explorationRefs: explorationRefs.map { $0.dto() },
            createdAt: carePackage.createdAt,
            updatedAt: carePackage.updatedAt
        )
    }
}

extension CarePackageDopeRefRecord {
    func dto() -> CarePackageDopeRefRow {
        CarePackageDopeRefRow(uuid: uuid, dopeCode: dopeCode, note: note, seq: Int(seq))
    }
}

extension CarePackageKbiteRefRecord {
    func dto() -> CarePackageKbiteRefRow {
        CarePackageKbiteRefRow(
            uuid: uuid,
            kbiteResourceFileUuid: kbiteResourceFileUuid,
            brief: brief,
            seq: Int(seq)
        )
    }
}

extension CarePackageExplorationRefRecord {
    func dto() -> CarePackageExplorationRefRow {
        CarePackageExplorationRefRow(
            uuid: uuid,
            curatedTitle: curatedTitle,
            curatedBody: curatedBody,
            filePath: filePath,
            sourceFindingUuid: sourceFindingUuid,
            seq: Int(seq)
        )
    }
}
