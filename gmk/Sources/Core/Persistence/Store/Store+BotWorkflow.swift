import Foundation
import GRDB

// BOT_* / PROMPT_START / PROMPT_RESUME — the daemon-held workflow state
// machine (m0025). Bodies live in BotWorkflowRepository; these wrappers own
// the transaction. Phase is DERIVED at every next — resume is the first-run
// code path by construction.

extension Store {

    /// Initiates a new bot workflow for a prompt.
    ///
    /// - Parameter req: The start request with prompt and phase information.
    /// - Returns: The workflow response with initial phase state.
    /// - Throws: Store errors or workflow initialization errors.
    func promptStart(_ req: PromptStartRequest) throws -> BotWorkflowResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).start(req) }
    }

    /// Resumes an existing bot workflow for a prompt.
    ///
    /// - Parameter req: The resume request with prompt and phase information.
    /// - Returns: The workflow response with current phase state.
    /// - Throws: Store errors or workflow resumption errors.
    func promptResume(_ req: PromptResumeRequest) throws -> BotWorkflowResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).resume(req) }
    }

    /// Advances the bot workflow to the next phase.
    ///
    /// - Parameter req: The next request with current workflow state.
    /// - Returns: The response with next phase information.
    /// - Throws: Store errors or phase transition errors.
    func botNext(_ req: BotNextRequest) throws -> BotNextResponse {
        try boundary { db in try BotWorkflowRepository(db: db, core: core).next(req) }
    }

    /// Fetches the current bot workflow state.
    ///
    /// - Parameter req: The get request with workflow identifiers.
    /// - Returns: The current workflow response.
    /// - Throws: Store errors or fetch errors.
    func botGet(_ req: BotGetRequest) throws -> BotWorkflowResponse {
        try boundaryRead { db in try BotWorkflowRepository(db: db, core: core).get(req) }
    }
}
