import Foundation
import GRDB

// AGENT_REGISTER — the spawner's authority write for one agent_id. The body
// lives in AgentRegistrationRepository; this wrapper owns the transaction.

extension Store {

    func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try boundary { db in
            try AgentRegistrationRepository(db: db, core: core).register(req)
        }
    }
}
