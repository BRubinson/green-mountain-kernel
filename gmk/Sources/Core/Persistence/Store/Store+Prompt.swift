import Foundation
import GRDB

// PROMPT_CREATE / PROMPT_LIST / PROMPT_GET / PROMPT_UPDATE_CONTENT /
// PROMPT_SET_STATUS — the prompt lifecycle, with the STAY TRUE convention
// (Draft-only content edits) and the forward-only transition table enforced
// here rather than by convention.
// Bodies live in PromptRepository; these wrappers own the transaction.

extension Store {
    /// Creates a new prompt for a session.
    /// - Parameter req: The request with session uuid and initial content.
    /// - Returns: The created prompt row.
    /// - Throws: Any database error or validation failure.
    func createPrompt(_ req: PromptCreateRequest) throws -> PromptRow {
        try boundary { db in try PromptRepository(db: db, core: core).create(req) }
    }

    /// Lists prompts for a session or all prompts.
    /// - Parameter req: The request with optional session uuid filter.
    /// - Returns: The list of prompt rows matching the filter.
    /// - Throws: Any database error.
    func listPrompts(_ req: PromptListRequest) throws -> PromptListResponse {
        try boundaryRead { db in try PromptRepository(db: db, core: core).list(req) }
    }

    /// Fetches a prompt with its reports.
    /// - Parameter req: The request with the prompt uuid.
    /// - Returns: The prompt row and optional report stubs.
    /// - Throws: `StoreError.notFound` if prompt not found.
    func getPrompt(_ req: PromptGetRequest) throws -> PromptGetResponse {
        try boundaryRead { db in try PromptRepository(db: db, core: core).get(req) }
    }

    /// Updates a prompt's content (backstory, goal, or detail).
    /// - Parameter req: The request with prompt uuid and fields to update.
    /// - Returns: The updated prompt row.
    /// - Throws: `StoreError.invalidEntityTransition` if prompt is not in draft status.
    func updatePromptContent(_ req: PromptUpdateContentRequest) throws -> PromptRow {
        try boundary { db in try PromptRepository(db: db, core: core).updateContent(req) }
    }

    /// Transitions a prompt to a new status.
    /// - Parameter req: The request with prompt uuid, target status, and expected version.
    /// - Returns: The updated prompt row.
    /// - Throws: `StoreError.invalidEntityTransition` if status change is invalid.
    func setPromptStatus(_ req: PromptSetStatusRequest) throws -> PromptRow {
        try boundary { db in try PromptRepository(db: db, core: core).setStatus(req) }
    }

    // MARK: - Cross-domain helper forward

    /// Fetches a prompt row by uuid within a database context.
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The prompt uuid.
    /// - Returns: The prompt row, or nil if not found.
    /// - Throws: Any database error during the fetch.
    func fetchPromptRow(_ db: Database, uuid: String) throws -> PromptRow? {
        try PromptRepository(db: db, core: core).fetchRow(uuid: uuid)
    }
}
