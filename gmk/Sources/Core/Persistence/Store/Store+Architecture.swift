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

    /// Opens a new architecture summary for the prompt.
    ///
    /// - Parameter req: Request containing the prompt UUID.
    /// - Returns: The newly opened summary.
    /// - Throws: `StoreError` on database failure.
    func archOpen(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).open(req) }
    }

    /// Summarizes an architecture proposal.
    ///
    /// - Parameter req: Request containing the architecture UUID and summary text.
    /// - Returns: The updated summary.
    /// - Throws: `StoreError` on database failure.
    func archSummarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).summarize(req) }
    }

    /// Adds a persistence layer change to the architecture.
    ///
    /// - Parameter req: Request containing the change to add.
    /// - Returns: The persisted change.
    /// - Throws: `StoreError` on database failure.
    func archPersistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).persistAdd(req) }
    }

    /// Adds a field layer change to the architecture.
    ///
    /// - Parameter req: Request containing the change to add.
    /// - Returns: The persisted change.
    /// - Throws: `StoreError` on database failure.
    func archFieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).fieldAdd(req) }
    }

    /// Adds a general layer change to the architecture.
    ///
    /// - Parameter req: Request containing the change to add.
    /// - Returns: The persisted change.
    /// - Throws: `StoreError` on database failure.
    func archGeneralAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).generalAdd(req) }
    }

    /// Transitions an architecture summary from drafting to proposed.
    ///
    /// - Parameter req: Request containing the summary UUID and expected version.
    /// - Returns: The updated summary.
    /// - Throws: `StoreError` on database failure or version conflict.
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

    /// Transitions an architecture summary from proposed to approved.
    ///
    /// - Parameter req: Request containing the summary UUID and expected version.
    /// - Returns: The updated summary.
    /// - Throws: `StoreError` on database failure or version conflict.
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

    /// Transitions an architecture summary from proposed back to drafting.
    ///
    /// - Parameter req: Request containing the summary UUID and expected version.
    /// - Returns: The updated summary.
    /// - Throws: `StoreError` on database failure or version conflict.
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

    /// Adds an architecture option to a proposal.
    ///
    /// - Parameter req: Request containing the option to add.
    /// - Returns: The persisted option.
    /// - Throws: `StoreError` on database failure.
    func archOptionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).optionAdd(req) }
    }

    /// Selects the winning option and seals the architecture.
    ///
    /// - Parameter req: Request containing the selected option UUID and expected version.
    /// - Returns: The decision result.
    /// - Throws: `StoreError` on database failure or version conflict.
    func archDecide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        try boundary { db in try ArchitectureRepository(db: db, core: core).decide(req) }
    }

    /// Fetches the architecture state for a summary.
    ///
    /// - Parameter req: Request containing the summary UUID.
    /// - Returns: The complete architecture state.
    /// - Throws: `StoreError` on database failure.
    func archGet(_ req: ArchGetRequest) throws -> ArchGetResponse {
        try boundaryRead { db in try ArchitectureRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

    /// Returns the instance root path for the prompt.
    ///
    /// The arch change-add paths normalize against the instance root reached via
    /// prompt → session → instance.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - promptUuid: The prompt UUID to look up.
    /// - Returns: The instance root path.
    /// - Throws: `StoreError` on database failure.
    func instanceRoot(_ db: Database, promptUuid: String) throws -> String {
        try ArchitectureRepository(db: db, core: core).instanceRoot(promptUuid: promptUuid)
    }
}
