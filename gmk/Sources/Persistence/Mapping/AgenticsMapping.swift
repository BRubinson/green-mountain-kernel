// db → wire for the agentics composites and their ref children.
//
// This is the only place a persistence type and a wire Row meet. Wire Rows
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension AgentBriefingWithRefs {
    /// Converts a briefing record with its references to a wire row.
    /// - Returns: A wire representation of the briefing with references.
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
    /// Converts a dope reference record to a wire row.
    /// - Returns: A wire representation of the dope reference.
    func dto() -> AgentBriefingDopeRefRow {
        AgentBriefingDopeRefRow(uuid: uuid, dopeCode: dopeCode, brief: brief, seq: Int(seq))
    }
}

extension AgentBriefingDopeKbiteRecord {
    /// Converts a kbite reference record to a wire row.
    /// - Returns: A wire representation of the kbite reference.
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
    /// Converts a file change reference record to a wire row.
    /// - Returns: A wire representation of the file change reference.
    func dto() -> AgentBriefingFileChangeRefRow {
        AgentBriefingFileChangeRefRow(uuid: uuid, fileChangeUuid: fileChangeUuid, seq: Int(seq))
    }
}

extension ClarificationQuestionWithOptions {
    /// Converts a question with options to a wire row.
    ///
    /// The selections are a junction read the caller batches across questions,
    /// so they arrive labelled and un-defaulted rather than as a second query
    /// hidden behind a default.
    ///
    /// - Parameter selectedOptionUuids: The selected option identifiers.
    /// - Returns: A wire representation of the question with options and selections.
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
    /// Converts an option record to a wire row.
    /// - Returns: A wire representation of the clarification option.
    func dto() -> ClarificationOptionRow {
        ClarificationOptionRow(uuid: uuid, seq: seq, body: body)
    }
}

extension ArchPersistenceChangeWithFields {
    /// Converts a persistence change with fields to a wire row.
    ///
    /// `implementation` is computed against the file-change trail, not read
    /// from this table, so it stays labelled and un-defaulted: a default would
    /// let a caller silently drop it.
    ///
    /// - Parameter implementation: The change implementation state.
    /// - Returns: A wire representation of the persistence change with fields.
    func dto(implementation: ChangeImplementationState) -> ArchPersistenceChangeRow {
        ArchPersistenceChangeRow(
            uuid: change.uuid,
            seq: change.seq,
            className: change.className,
            filePath: change.filePath,
            reasonBrief: change.reasonBrief,
            fields: fields.map { $0.dto() },
            implementation: implementation,
            changeKind: change.changeKind,
            dopeRef: change.dopeRef
        )
    }
}

extension ArchitecturePersistenceFieldChangeRecord {
    /// Converts a field change record to a wire row.
    /// - Returns: A wire representation of the field change.
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
    /// Converts a general change record to a wire row.
    ///
    /// See the persistence twin above for why `implementation` is labelled and
    /// un-defaulted.
    ///
    /// - Parameter implementation: The change implementation state.
    /// - Returns: A wire representation of the general change.
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

extension ArchitectureSummaryRecord {
    /// Converts a summary record to a wire row.
    /// - Returns: A wire representation of the architecture summary.
    func dto() -> ArchitectureSummaryRow {
        ArchitectureSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            body: body,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            decisionRationale: decisionRationale
        )
    }
}

extension ArchitectureOptionRecord {
    /// Converts an option record to a wire row.
    /// - Returns: A wire representation of the architecture option.
    func dto() -> ArchitectureOptionRow {
        ArchitectureOptionRow(
            uuid: uuid,
            version: version,
            architectureSummaryUuid: architectureSummaryUuid,
            agentName: agentName,
            agentId: agentId,
            body: body,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension ClarificationSummaryRecord {
    /// Converts a clarification summary record to a wire row.
    /// - Returns: A wire representation of the clarification summary.
    func dto() -> ClarificationSummaryRow {
        ClarificationSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension InternalClarificationNoteRecord {
    /// Converts a note record to a wire row.
    ///
    /// `weight` narrows `Int64` (the column type) to the wire's `Int`,
    /// explicitly and non-truncating.
    ///
    /// - Returns: A wire representation of the clarification note.
    func dto() -> ClarificationNoteRow {
        ClarificationNoteRow(
            uuid: uuid,
            version: version,
            clarificationSummaryUuid: clarificationSummaryUuid,
            body: body,
            confusedEntityUuid: confusedEntityUuid,
            confusedEntityType: confusedEntityType,
            weight: weight.map(Int.init),
            questionUuid: questionUuid,
            agentId: agentId,
            agentName: agentName
        )
    }
}

extension ExplorationSummaryRecord {
    /// Converts an exploration summary record to a wire row.
    /// - Returns: A wire representation of the exploration summary.
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
    /// Converts a finding record to a wire row.
    ///
    /// `findingRating` narrows `Int64` (the column type) to the wire's `Int`,
    /// explicitly and non-truncating.
    ///
    /// - Returns: A wire representation of the exploration finding.
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
    /// Converts a review summary record to a wire row.
    /// - Returns: A wire representation of the review summary.
    func dto() -> ReviewSummaryRow {
        ReviewSummaryRow(
            uuid: uuid,
            version: version,
            promptUuid: promptUuid,
            status: status,
            verdict: verdict,
            overview: overview,
            createdAt: createdAt,
            updatedAt: updatedAt,
            agentId: agentId
        )
    }
}

extension ReviewFindingRecord {
    /// Converts a finding record to a wire row.
    ///
    /// `lineStart`, `lineEnd` and `findingRating` narrow `Int64` (the column
    /// type) to the wire's `Int`, explicitly and non-truncating.
    ///
    /// - Returns: A wire representation of the review finding.
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
    /// Converts a file change with ranges to a wire row.
    /// - Returns: A wire representation of the file change with ranges.
    func dto() -> FileChangeRow {
        FileChangeRow(
            uuid: fileChange.uuid,
            sessionUuid: fileChange.sessionUuid,
            promptUuid: fileChange.promptUuid,
            relativePath: relativePath,
            changeKind: fileChange.changeKind,
            createdAt: fileChange.createdAt,
            ranges: ranges.map { $0.dto() },
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
            agentRegistrationUuid: fileChange.agentRegistrationUuid
        )
    }
}

extension FileChangeRangeRecord {
    /// Converts a range record to a wire row.
    /// - Returns: A wire representation of the change range.
    func dto() -> ChangeRangeRow {
        ChangeRangeRow(lineStart: Int(lineStart), lineEnd: Int(lineEnd))
    }
}

extension CarePackageWithRefs {
    /// Converts a care package with references to a wire row.
    /// - Returns: A wire representation of the care package with references.
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

extension TouchedPathSummary {
    /// Converts a touched path summary to a wire row.
    ///
    /// - Returns: A wire representation of the unplanned change.
    func dto() -> UnplannedChangeRow {
        UnplannedChangeRow(
            path: path,
            changeCount: changeCount,
            firstChangedAt: firstChangedAt,
            lastChangedAt: lastChangedAt
        )
    }
}

extension BotWorkflowRecord {
    /// Converts a workflow record to a wire row.
    ///
    /// - Returns: A wire representation of the bot workflow.
    func dto() -> BotWorkflowRow {
        BotWorkflowRow(
            uuid: uuid,
            version: version,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            variant: variant,
            status: status,
            clientKey: clientKey,
            lastServedPhase: lastServedPhase,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CarePackageDopeRefRecord {
    /// Converts a dope reference record to a wire row.
    /// - Returns: A wire representation of the care package dope reference.
    func dto() -> CarePackageDopeRefRow {
        CarePackageDopeRefRow(uuid: uuid, dopeCode: dopeCode, note: note, seq: Int(seq))
    }
}

extension CarePackageKbiteRefRecord {
    /// Converts a kbite reference record to a wire row.
    /// - Returns: A wire representation of the care package kbite reference.
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
    /// Converts an exploration reference record to a wire row.
    /// - Returns: A wire representation of the care package exploration reference.
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

extension AgentRegistrationRecord {
    /// Converts a registration record to a wire row.
    ///
    /// Every field is already on the row; no transformation occurs.
    ///
    /// - Returns: A wire representation of the agent registration.
    func dto() -> AgentRegistrationRow {
        AgentRegistrationRow(
            uuid: uuid,
            version: version,
            agentId: agentId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            claudeSessionId: claudeSessionId,
            claudeTurnId: claudeTurnId,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            agentType: agentType,
            role: role,
            methodology: methodology,
            workflowPhase: workflowPhase
        )
    }
}

extension PromptArtifactRecord {
    /// Converts an artifact record to a wire row.
    /// - Returns: A wire representation of the artifact.
    func dto() -> ArtifactRow {
        ArtifactRow(
            uuid: uuid,
            promptUuid: promptUuid,
            filePath: filePath,
            note: note,
            createdAt: createdAt
        )
    }
}

extension PromptQualifiedDiagramRecord {
    /// Converts a diagram record to a wire row.
    /// - Returns: A wire representation of the qualified diagram.
    func dto() -> PromptQualifiedDiagramRow {
        PromptQualifiedDiagramRow(
            uuid: uuid,
            promptUuid: promptUuid,
            diagramUuid: diagramUuid,
            renderedPath: renderedPath,
            renderedRevision: renderedRevision,
            renderFingerprint: renderFingerprint,
            qualification: qualification,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
