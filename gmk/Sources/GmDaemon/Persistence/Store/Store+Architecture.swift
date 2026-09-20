import Foundation
import GRDB

// ARCH_* — the db-native architecture machine (replaces architecture.md).
// drafting → proposed → approved, plus the proposed → drafting revision edge.
// The summary body is concept-level only; specific file changes are the
// normalized persistence/general change rows the implementation agent
// executes against — persistence rows always first (they are the backbone
// every other change builds on). ARCH_GET derives implementation state from
// the path join against file_change at read time: never stored, never stale.
// Bodies live in ArchitectureRepository; these wrappers own the transaction.

extension Store {

    /// Inline change_code cap, mirroring the kbite inline-content idiom.
    static let maxChangeCodeBytes = 2 * 1024 * 1024

    // MARK: - Verbs

    func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).open(req) }
    }

    func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).summarize(req) }
    }

    func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).persistAdd(req) }
    }

    func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).fieldAdd(req) }
    }

    func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).generalAdd(req) }
    }

    func archPropose(_ req: ArchProposeRequest) throws -> ArchSummaryResponse {
        try boundary { db in
            try ArchitectureRepository(db: db, core: core)
                .transition(
                    summaryUuid: req.summaryUuid,
                    expectedVersion: req.expectedVersion,
                    to: .proposed,
                    action: "propose",
                    requireFrom: .drafting
                )
        }
    }

    func archApprove(_ req: ArchApproveRequest) throws -> ArchSummaryResponse {
        try boundary { db in
            try ArchitectureRepository(db: db, core: core)
                .transition(
                    summaryUuid: req.summaryUuid,
                    expectedVersion: req.expectedVersion,
                    to: .approved,
                    action: "approve",
                    requireFrom: .proposed
                )
        }
    }

    func archRevise(_ req: ArchReviseRequest) throws -> ArchSummaryResponse {
        try boundary { db in
            try ArchitectureRepository(db: db, core: core)
                .transition(
                    summaryUuid: req.summaryUuid,
                    expectedVersion: req.expectedVersion,
                    to: .drafting,
                    action: "revise",
                    requireFrom: .proposed
                )
        }
    }

    func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).optionAdd(req) }
    }

    func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).decide(req) }
    }

    func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try boundaryRead { db in try ArchitectureRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

    /// The arch change-add paths normalize against the instance root reached
    /// via prompt → session → instance.
    func instanceRoot(_ db: Database, promptUuid: String) throws -> String {
        try ArchitectureRepository(db: db, core: core).instanceRoot(promptUuid: promptUuid)
    }
}
