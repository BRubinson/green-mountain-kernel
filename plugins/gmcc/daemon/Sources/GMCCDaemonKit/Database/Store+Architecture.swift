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

    public func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).open(req) }
    }

    public func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).summarize(req) }
    }

    public func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).persistAdd(req) }
    }

    public func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).fieldAdd(req) }
    }

    public func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).generalAdd(req) }
    }

    public func archPropose(_ req: ArchProposeRequest) throws -> ArchSummaryResponse {
        try dbQueue.write { db in
            try ArchitectureRepository(db: db, core: core).transition(
                summaryUuid: req.summaryUuid, expectedVersion: req.expectedVersion,
                to: .proposed, action: "propose", requireFrom: .drafting)
        }
    }

    public func archApprove(_ req: ArchApproveRequest) throws -> ArchSummaryResponse {
        try dbQueue.write { db in
            try ArchitectureRepository(db: db, core: core).transition(
                summaryUuid: req.summaryUuid, expectedVersion: req.expectedVersion,
                to: .approved, action: "approve", requireFrom: .proposed)
        }
    }

    public func archRevise(_ req: ArchReviseRequest) throws -> ArchSummaryResponse {
        try dbQueue.write { db in
            try ArchitectureRepository(db: db, core: core).transition(
                summaryUuid: req.summaryUuid, expectedVersion: req.expectedVersion,
                to: .drafting, action: "revise", requireFrom: .proposed)
        }
    }

    public func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).optionAdd(req) }
    }

    public func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try dbQueue.write { db in try ArchitectureRepository(db: db, core: core).decide(req) }
    }

    public func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try dbQueue.read { db in try ArchitectureRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards




    /// The arch change-add paths normalize against the instance root reached
    /// via prompt → session → instance.
    func instanceRoot(_ db: Database, promptUuid: String) throws -> String {
        try ArchitectureRepository(db: db, core: core).instanceRoot(promptUuid: promptUuid)
    }
}
