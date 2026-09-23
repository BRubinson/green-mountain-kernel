import Foundation
import GRDB

// AGENT_REGISTER — the spawner's authority write for one agent_id. The body
// lives in AgentRegistrationRepository; this wrapper owns the transaction.

extension Store {

    /// Registers an agent with the authority write for one agent id.
    ///
    /// The registration body lives in `AgentRegistrationRepository`; this wrapper
    /// owns the transaction.
    ///
    /// - Parameter req: The agent registration request.
    /// - Returns: The registration response.
    /// - Throws: Database errors or registration validation failures.
    func agentRegister(_ req: AgentRegisterRequest) throws -> AgentRegisterResponse {
        try boundary { db in
            try AgentRegistrationRepository(db: db, core: core).register(req)
        }
    }
}
