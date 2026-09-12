import Foundation
import GRDB

/// AGENT_REGISTER data access plus the on-demand identity write the
/// file_change path leans on. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
///
/// ONE ROW PER agent_id, written by two parties that never coordinate: the
/// SubagentStart hook supplies IDENTITY, the spawner supplies AUTHORITY. Every
/// write MERGES — a field the caller did not name keeps whatever the row
/// already holds — so neither party can erase the other's half and neither has
/// to go first.
struct AgentRegistrationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    /// As much of the identity half as a payload-borne write carries. Passed
    /// as one value so `ensureRegistration` reads as the single decision it
    /// is, rather than as six positional arguments a caller can transpose.
    struct AgentIdentity {
        let agentType: String?
        let claudeSessionId: String?
        let claudeTurnId: String?
        let sessionUuid: String?
        let promptUuid: String?
    }

    /// The registry's one write door, used by both writers: the spawner's
    /// authority half (role, methodology, the phase the agent was spawned
    /// for) and the SubagentStart hook's identity half (agent_type and the
    /// Claude ids). Creates the row for whichever of the two arrives first.
    ///
    /// MERGE, never overwrite: only the fields this request names are
    /// assigned, so neither half can blank the other (and a bare `--agent-id`
    /// call is a no-op read that proves a row exists). The merge is by field
    /// rather than by row VERSION on purpose — the two writers cannot hold
    /// each other's version, and making them try would reintroduce the
    /// ordering constraint the read-time join removes.
    ///
    /// THE GMCC SESSION AND PROMPT ARE DERIVED, NEVER PASSED. An identity
    /// write names a Claude conversation, and a conversation resolves through
    /// claude_session_binding — the same single path a file_change takes, so
    /// a registration cannot land in a session the binding disagrees with.
    func register(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        let agentId = req.agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentId.isEmpty else {
            throw StoreError.badRequest(detail: "agent_id is empty")
        }
        var assigned: [String: (any DatabaseValueConvertible)?] = [:]
        if let role = req.role { assigned["role"] = role }
        if let methodology = req.methodology { assigned["methodology"] = methodology }
        if let workflowPhase = req.workflowPhase { assigned["workflow_phase"] = workflowPhase }
        if let agentType = req.agentType { assigned["agent_type"] = agentType }
        if let claudeTurnId = req.claudeTurnId { assigned["claude_turn_id"] = claudeTurnId }
        if let claudeSessionId = req.claudeSessionId {
            assigned["claude_session_id"] = claudeSessionId
            // An unbound conversation leaves both uuids NULL rather than
            // failing the registration: the agent still gets its identity
            // row, and the FK the file_change path depends on still resolves.
            if let sessionUuid = try claudeSessionBinding.resolveSession(
                claudeSessionId: claudeSessionId) {
                assigned["session_uuid"] = sessionUuid
                // Assigned only when the ladder answers. A nil here would be
                // written as NULL, and blanking a prompt the other writer
                // already recorded is exactly the overwrite this merge exists
                // to prevent.
                if let promptUuid = try fileChange.resolveAttributedPrompt(
                    sessionUuid: sessionUuid) {
                    assigned["prompt_uuid"] = promptUuid
                }
            }
        }

        if let existing = try fetch(agentId: agentId) {
            guard !assigned.isEmpty else {
                return AgentRegisterResponse(registration: existing.wireRow(), created: false)
            }
            try core.updateBase(
                db, table: "agent_registration", uuid: existing.uuid,
                expectedVersion: existing.version, set: assigned)
            return AgentRegisterResponse(
                registration: try require(agentId: agentId).wireRow(), created: false)
        }
        assigned["agent_id"] = agentId
        _ = try core.insertBase(db, table: "agent_registration", extra: assigned)
        return AgentRegisterResponse(
            registration: try require(agentId: agentId).wireRow(), created: true)
    }

    /// The file_change path's registration resolver — and the reason
    /// "registration first" is a GUARANTEE rather than a precondition.
    ///
    /// A real FK enforced literally would DROP an agent's change whenever a
    /// SubagentStart never ran, which is a new silent failure inside the work
    /// that exists to delete one. So a missing registration is CREATED here
    /// from the payload instead: agent_id, agent_type and the Claude ids are
    /// all on it, and the role/methodology/workflow_phase the spawner owns
    /// stay NULL for its later merge (UNIQUE(agent_id) makes that the same
    /// row). Nothing is ever dropped for want of a registration.
    ///
    /// An invented registration is NOT silent — it appends AGENT_UNREGISTERED,
    /// because it means the spawner never registered and that is exactly what
    /// we want to know.
    ///
    /// Returns nil for the PRIMARY, which carries no agent_id at all: that
    /// absence is the primary/subagent discriminator, and a primary write has
    /// no identity to point at.
    func ensureRegistration(agentId: String?, from identity: AgentIdentity) throws -> String? {
        guard let raw = agentId else { return nil }
        let agentId = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agentId.isEmpty else { return nil }
        if let existing = try fetch(agentId: agentId) { return existing.uuid }

        let uuid = try core.insertBase(db, table: "agent_registration", extra: [
            "agent_id": agentId,
            "agent_type": identity.agentType,
            "claude_session_id": identity.claudeSessionId,
            "claude_turn_id": identity.claudeTurnId,
            "session_uuid": identity.sessionUuid,
            "prompt_uuid": identity.promptUuid,
        ])
        // JSONSerialization rejects a wrapped Optional, so absent facts are
        // absent KEYS rather than nulls.
        var payload: [String: Any] = ["agent_id": agentId]
        if let agentType = identity.agentType { payload["agent_type"] = agentType }
        if let sessionUuid = identity.sessionUuid { payload["session_uuid"] = sessionUuid }
        if let promptUuid = identity.promptUuid { payload["prompt_uuid"] = promptUuid }
        try core.appendEvent(
            db, kind: .agentUnregistered, subjectUuid: uuid,
            payload: Store.jsonPayload(payload))
        return uuid
    }

    // MARK: - Lookup

    func fetch(agentId: String) throws -> AgentRegistrationRecord? {
        try AgentRegistrationRecord.fetchOne(db, where: "agent_id = ?", arguments: [agentId])
    }

    private func require(agentId: String) throws -> AgentRegistrationRecord {
        guard let row = try fetch(agentId: agentId) else {
            throw StoreError.notFound(entity: "agent_registration", key: agentId)
        }
        return row
    }
}
