import Foundation
import GRDB

// AGENT_REGISTER — the spawner's authority write for one agent_id. The body
// lives in AgentRegistrationRepository; this wrapper owns the transaction.

extension Store {

    public func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try dbQueue.write { db in
            try AgentRegistrationRepository(db: db, core: core).register(req)
        }
    }
}
