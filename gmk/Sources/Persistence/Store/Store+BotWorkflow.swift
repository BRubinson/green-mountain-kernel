import Foundation
import GRDB

// BOT_* / PROMPT_START / PROMPT_RESUME — the daemon-held workflow state
// machine (m0025). Bodies live in BotWorkflowRepository; these wrappers own
// the transaction. Phase is DERIVED at every next — resume is the first-run
// code path by construction.

extension Store {

    func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).start(req) }
    }

    func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).resume(req) }
    }

    func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).next(req) }
    }

    func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try boundaryRead { db in try BotWorkflowRepository(db: db, core: core).get(req) }
    }
}
