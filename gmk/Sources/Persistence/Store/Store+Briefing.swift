import Foundation
import GRDB

// BRIEFING_* — the agent-briefing machine: the context package a briefer
// assembles for a phase, pulled by spawned agents at start.
//
// A briefing is spawn-time plumbing consumed once, so there is no findings
// machinery, no FTS mirror, and a two-state gate rather than a status machine.
// OPEN on an existing (owner, step) pair RESETS the row to building: a step's
// briefing is always its CURRENT briefing. Staleness is COMPUTED at every read
// and only ever WARNS. Bodies live in BriefingRepository.

/// Registry-governed vocabularies (the m0021 element_type rule): the columns
/// carry NO db CHECK, so a future step or status is an entry here — never a
/// migration.
///
/// The role map is what lets BRIEFING_STUB resolve an agent
/// type to its step without the hook script knowing anything.
enum BriefingStepSpec {
    /// m0025: pre_architecture is RETIRED — the care package replaced it
    /// (existing rows were retagged to initial by the migration).
    ///
    /// A future
    /// step is still a registry entry, never a migration.
    static let steps: [String] = ["initial"]
    static let statuses: [String] = ["building", "ready"]

    /// agent role (plugin-scoped name with or without the `gmcc:` prefix) →
    /// the step that role consumes.
    ///
    /// Roles absent here get no briefing line in
    /// their stub — deliberately, not an error. code-architect dropped out
    /// with pre_architecture: architects load the care package instead.
    static let roleStepMap: [String: String] = [
        "briefer": "initial",
        "code-explorer": "initial",
    ]

    /// Validates a briefing step name.
    /// - Parameter raw: The step name to validate.
    /// - Returns: The validated step name.
    /// - Throws: `StoreError.badRequest` when the step is unknown.
    static func validateStep(_ raw: String) throws -> String {
        guard steps.contains(raw) else {
            throw StoreError.badRequest(
                detail: "unknown briefing step '\(raw)' — known: \(steps.joined(separator: ", "))"
            )
        }
        return raw
    }

    /// Returns the briefing step for an agent type.
    /// - Parameter agentType: The agent role name, with or without the `gmcc:` prefix.
    /// - Returns: The step name, or `nil` if the agent has no briefing.
    static func step(forAgentType agentType: String) -> String? {
        let bare =
            agentType.hasPrefix("gmcc:")
            ? String(agentType.dropFirst("gmcc:".count))
            : agentType
        return roleStepMap[bare]
    }
}

extension Store {

    // MARK: - Verbs

    /// Opens a briefing for an agent spawn.
    /// - Parameter req: The open request.
    /// - Returns: The briefing row.
    /// - Throws: `StoreError` on validation or database failure.
    func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try boundary { db in try BriefingRepository(db: db, core: core).open(req) }
    }

    /// Marks a briefing as complete.
    /// - Parameter req: The completion request.
    /// - Returns: The briefing row.
    /// - Throws: `StoreError` on validation or database failure.
    func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try boundary { db in try BriefingRepository(db: db, core: core).complete(req) }
    }

    /// Fetches a briefing row.
    /// - Parameter req: The fetch request.
    /// - Returns: The briefing response.
    /// - Throws: `StoreError` on validation or database failure.
    func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).get(req) }
    }

    /// Lists briefing rows.
    /// - Parameter req: The list request.
    /// - Returns: The briefing list response.
    /// - Throws: `StoreError` on validation or database failure.
    func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).list(req) }
    }

    /// Builds a briefing stub for agent spawn.
    ///
    /// Empty stub with success when nothing applies — the hook must never
    /// wedge a spawn.
    /// - Parameter req: The briefing stub request.
    /// - Returns: The briefing stub response.
    /// - Throws: `StoreError` on database failure.
    func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).stub(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Fetches a briefing row by identifier.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The briefing row identifier.
    /// - Returns: The briefing row, or `nil` if not found.
    /// - Throws: `StoreError` on database failure.
    func fetchBriefing(_ db: Database, uuid: String) throws -> AgentBriefingRow? {
        try BriefingRepository(db: db, core: core).fetchBriefing(uuid: uuid)
    }

    // MARK: - JSON helpers (deterministic encodings for TEXT-JSON columns)

    /// Encodes strings to deterministic JSON.
    /// - Parameter strings: The array to encode.
    /// - Returns: A JSON string.
    /// - Throws: Encoding errors.
    static func encodeJsonArray(_ strings: [String]) throws -> String {
        let data = try JSONEncoder().encode(strings)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Encodes string dictionaries to deterministic JSON.
    /// - Parameter objects: The array of dictionaries to encode.
    /// - Returns: A JSON string.
    /// - Throws: Encoding errors.
    static func encodeJsonObjectArray(_ objects: [[String: String?]]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(objects)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
