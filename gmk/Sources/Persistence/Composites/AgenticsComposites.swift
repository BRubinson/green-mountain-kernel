// GRDB-native composite records for the agentics tables.
//
// A composite is FetchableRecord + Decodable whose properties are Records or
// arrays of Records. Each property name equals the `forKey` name of the
// association that supplies it; the one property naming no association decodes
// from the base row itself. No property maps to a column, so the composite
// needs no column-decoding strategy: every child decodes with its own.

import Foundation
import GRDB

/// One `agent_briefing` row with its three ref classes, fetched in four
/// statements by GRDB rather than one per briefing.
struct AgentBriefingWithRefs: FetchableRecord, Decodable {
    var agentBriefing: AgentBriefingRecord
    var dopeRefs: [AgentBriefingDopePersistenceRecord]
    var kbiteRefs: [AgentBriefingDopeKbiteRecord]
    var fileChangeRefs: [AgentSessionFileChangeRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        AgentBriefingRecord
            .including(all: AgentBriefingRecord.dopeRefs)
            .including(all: AgentBriefingRecord.kbiteRefs)
            .including(all: AgentBriefingRecord.fileChangeRefs)
            .asRequest(of: Self.self)
    }
}

/// One `care_package` row with its three ref classes.
struct CarePackageWithRefs: FetchableRecord, Decodable {
    var carePackage: CarePackageRecord
    var dopeRefs: [CarePackageDopeRefRecord]
    var kbiteRefs: [CarePackageKbiteRefRecord]
    var explorationRefs: [CarePackageExplorationRefRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        CarePackageRecord
            .including(all: CarePackageRecord.dopeRefs)
            .including(all: CarePackageRecord.kbiteRefs)
            .including(all: CarePackageRecord.explorationRefs)
            .asRequest(of: Self.self)
    }
}
