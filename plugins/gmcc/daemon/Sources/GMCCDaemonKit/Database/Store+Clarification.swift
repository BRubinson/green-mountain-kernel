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

    public func clarifyOpen(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).open(req) }
    }

    public func clarifyQuestionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).questionAdd(req) }
    }

    public func clarifyNoteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).noteAdd(req) }
    }

    public func carePackageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).packageOpen(req) }
    }

    public func carePackageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).packageRefAdd(req) }
    }

    public func carePackageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).packageComplete(req) }
    }

    public func carePackageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        try dbQueue.read { db in try ClarificationRepository(db: db, core: core).packageGet(req) }
    }

    public func clarifySeal(_ req: ClarifySealRequest) throws -> ClarifySummaryResponse {
        try dbQueue.write { db in
            try ClarificationRepository(db: db, core: core).transition(
                summaryUuid: req.summaryUuid, expectedVersion: req.expectedVersion,
                to: .answering, action: "seal", requireFrom: .building)
        }
    }

    public func clarifyReopen(_ req: ClarifyReopenRequest) throws -> ClarifySummaryResponse {
        try dbQueue.write { db in
            try ClarificationRepository(db: db, core: core).transition(
                summaryUuid: req.summaryUuid, expectedVersion: req.expectedVersion,
                to: .answering, action: "reopen", requireFrom: .complete)
        }
    }

    public func clarifyAnswer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).answer(req) }
    }

    public func clarifyFinalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        try dbQueue.write { db in try ClarificationRepository(db: db, core: core).finalize(req) }
    }

    public func clarifyGet(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        try dbQueue.read { db in try ClarificationRepository(db: db, core: core).get(req) }
    }

    // MARK: - Cross-domain helper forwards


    /// Item 3 helper shared by the clarify/arch mutation paths: prompt-scoped
    /// writes advance session recency without bumping the session version.
    func touchSessionForPrompt(_ db: Database, promptUuid: String) throws {
        try ClarificationRepository(db: db, core: core).touchSessionForPrompt(promptUuid: promptUuid)
    }



}
