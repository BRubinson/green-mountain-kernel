import Foundation
import GRDB

// BOT_* / PROMPT_START / PROMPT_RESUME — the daemon-held workflow state
// machine (m0025). Bodies live in BotWorkflowRepository; these wrappers own
// the transaction. Phase is DERIVED at every next — resume is the first-run
// code path by construction.

extension Store {

    public func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try dbQueue.write { db in try BotWorkflowRepository(db: db, core: core).start(req) }
    }

    public func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try dbQueue.write { db in try BotWorkflowRepository(db: db, core: core).resume(req) }
    }

    public func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try dbQueue.write { db in try BotWorkflowRepository(db: db, core: core).next(req) }
    }

    public func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try dbQueue.read { db in try BotWorkflowRepository(db: db, core: core).get(req) }
    }
}
