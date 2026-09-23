import Foundation
import GRDB

// CLARIFY_* — the db-native clarification machine (replaces qualified.md).
// building → answering → complete, plus the complete → answering revision
// edge. Clarify verbs NEVER touch prompt.status — PROMPT_SET_STATUS is the
// single front door for prompt transitions; the shared ensure helper is what
// both doors call, so UNIQUE(prompt_uuid) can never double-create.
// Bodies live in ClarificationRepository; these wrappers own the transaction.

extension Store {

    // MARK: - Verbs

    /// Opens a clarification workflow for the given request.
    ///
    /// - Parameter req: The clarification open request containing the prompt.
    /// - Returns: A summary response with the opened clarification state.
    /// - Throws: A store error if the operation fails.
    func clarifyOpen(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).open(req) }
    }

    /// Adds a clarification question to an open clarification.
    ///
    /// - Parameter req: The question add request with the question text.
    /// - Returns: The added question row with its identifier.
    /// - Throws: A store error if the operation fails.
    func clarifyQuestionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).questionAdd(req) }
    }

    /// Adds a clarification note to an open clarification.
    ///
    /// - Parameter req: The note add request with the note text.
    /// - Returns: The added note row with its identifier.
    /// - Throws: A store error if the operation fails.
    func clarifyNoteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).noteAdd(req) }
    }

    /// Opens a new care package for a clarification.
    ///
    /// - Parameter req: The care package open request.
    /// - Returns: The opened care package response.
    /// - Throws: A store error if the operation fails.
    func carePackageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).packageOpen(req) }
    }

    /// Adds a resource reference to a care package.
    ///
    /// - Parameter req: The reference add request with the resource identifier.
    /// - Returns: The updated care package response.
    /// - Throws: A store error if the operation fails.
    func carePackageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).packageRefAdd(req) }
    }

    /// Completes a care package and marks it as ready.
    ///
    /// - Parameter req: The care package complete request.
    /// - Returns: The completed care package response.
    /// - Throws: A store error if the operation fails.
    func carePackageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).packageComplete(req) }
    }

    /// Retrieves a care package by its identifier.
    ///
    /// - Parameter req: The care package get request with the package id.
    /// - Returns: The care package response.
    /// - Throws: A store error if the package is not found.
    func carePackageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        try boundaryRead { db in try ClarificationRepository(db: db, core: core).packageGet(req) }
    }

    /// Seals a clarification and transitions it to the answering state.
    ///
    /// - Parameter req: The seal request with the summary uuid and version.
    /// - Returns: The updated clarification summary response.
    /// - Throws: A store error if the transition fails.
    func clarifySeal(_ req: ClarifySealRequest) throws -> ClarifySummaryResponse {
        try boundary { db in
            try ClarificationRepository(db: db, core: core)
                .transition(
                    summaryUuid: req.summaryUuid,
                    expectedVersion: req.expectedVersion,
                    to: .answering,
                    action: "seal",
                    requireFrom: .building
                )
        }
    }

    /// Reopens a completed clarification and returns it to answering state.
    ///
    /// - Parameter req: The reopen request with the summary uuid and version.
    /// - Returns: The updated clarification summary response.
    /// - Throws: A store error if the transition fails.
    func clarifyReopen(_ req: ClarifyReopenRequest) throws -> ClarifySummaryResponse {
        try boundary { db in
            try ClarificationRepository(db: db, core: core)
                .transition(
                    summaryUuid: req.summaryUuid,
                    expectedVersion: req.expectedVersion,
                    to: .answering,
                    action: "reopen",
                    requireFrom: .complete
                )
        }
    }

    /// Records an answer to a clarification question.
    ///
    /// - Parameter req: The answer request with the question id and answer text.
    /// - Returns: The updated question row.
    /// - Throws: A store error if the operation fails.
    func clarifyAnswer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).answer(req) }
    }

    /// Finalizes a clarification and marks it complete.
    ///
    /// - Parameter req: The finalize request with clarification details.
    /// - Returns: The finalize response with completion status.
    /// - Throws: A store error if the operation fails.
    func clarifyFinalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        try boundary { db in try ClarificationRepository(db: db, core: core).finalize(req) }
    }

    /// Retrieves a clarification by its identifier.
    ///
    /// - Parameter req: The clarify get request with the summary uuid.
    /// - Returns: The clarification details response.
    /// - Throws: A store error if the clarification is not found.
    func clarifyGet(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        try boundaryRead { db in try ClarificationRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards

    /// Advances a session's last-activity time for a prompt operation.
    ///
    /// Item 3 helper shared by the clarify/arch mutation paths: prompt-scoped
    /// writes advance session recency without bumping the session version.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - promptUuid: The prompt's identifier.
    /// - Throws: A database error if the update fails.
    func touchSessionForPrompt(_ db: Database, promptUuid: String) throws {
        try ClarificationRepository(db: db, core: core).touchSessionForPrompt(promptUuid: promptUuid)
    }

}
