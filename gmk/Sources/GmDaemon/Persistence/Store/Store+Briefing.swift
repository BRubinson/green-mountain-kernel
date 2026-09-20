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
/// migration. The role map is what lets BRIEFING_STUB resolve an agent
/// type to its step without the hook script knowing anything.
enum BriefingStepSpec {
    /// m0025: pre_architecture is RETIRED — the care package replaced it
    /// (existing rows were retagged to initial by the migration). A future
    /// step is still a registry entry, never a migration.
    static let steps: [String] = ["initial"]
    static let statuses: [String] = ["building", "ready"]

    /// agent role (plugin-scoped name with or without the `gmcc:` prefix) →
    /// the step that role consumes. Roles absent here get no briefing line in
    /// their stub — deliberately, not an error. code-architect dropped out
    /// with pre_architecture: architects load the care package instead.
    static let roleStepMap: [String: String] = [
        "briefer": "initial",
        "code-explorer": "initial",
    ]

    static func validateStep(_ raw: String) throws -> String {
        guard steps.contains(raw) else {
            throw StoreError.badRequest(
                detail: "unknown briefing step '\(raw)' — known: \(steps.joined(separator: ", "))"
            )
        }
        return raw
    }

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

    func briefingOpen(_ req: BriefingOpenRequest) throws -> BriefingRowResponse {
        try boundary { db in try BriefingRepository(db: db, core: core).open(req) }
    }

    func briefingComplete(_ req: BriefingCompleteRequest) throws -> BriefingRowResponse {
        try boundary { db in try BriefingRepository(db: db, core: core).complete(req) }
    }

    func briefingGet(_ req: BriefingGetRequest) throws -> BriefingGetResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).get(req) }
    }

    func briefingList(_ req: BriefingListRequest) throws -> BriefingListResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).list(req) }
    }

    /// The SubagentStart hook's one call. Empty stub + success when nothing
    /// applies — the hook must never wedge a spawn.
    func briefingStub(_ req: BriefingStubRequest) throws -> BriefingStubResponse {
        try boundaryRead { db in try BriefingRepository(db: db, core: core).stub(req) }
    }

    // MARK: - Cross-domain helper forward

    func fetchBriefing(_ db: Database, uuid: String) throws -> AgentBriefingRow? {
        try BriefingRepository(db: db, core: core).fetchBriefing(uuid: uuid)
    }

    // MARK: - JSON helpers (deterministic encodings for TEXT-JSON columns)

    static func encodeJsonArray(_ strings: [String]) throws -> String {
        let data = try JSONEncoder().encode(strings)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func encodeJsonObjectArray(_ objects: [[String: String?]]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(objects)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
