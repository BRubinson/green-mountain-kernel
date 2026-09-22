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
