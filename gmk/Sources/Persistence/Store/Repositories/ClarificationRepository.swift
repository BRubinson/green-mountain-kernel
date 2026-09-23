import Foundation
import GRDB

/// CLARIFY_* / CARE_PACKAGE_* data access — the db-native clarification
/// machine.
///
/// Runs INSIDE Store-owned transaction; holds no dbQueue, never self-transacts.
/// Summary is a slim status machine; questions and notes are content; care
/// package is the standalone clarified-intent bundle. FINALIZE IS A PURE GATE,
/// never writes prompt row (content is human input only).
struct ClarificationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Returns the existing clarification summary or creates one at `building`.
    ///
    /// Idempotent; CLARIFY_OPEN is its only caller, so opening a clarification
    /// is something an agent does deliberately, never a side effect of moving
    /// a status.
    ///
    /// - Parameter promptUuid: The prompt this summary belongs to.
    /// - Returns: A tuple of the summary uuid and a boolean indicating whether
    ///   it was newly created.
    /// - Throws: `StoreError.notFound` if the prompt does not exist.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing =
            try ClarificationSummaryRecord
            .all()
            .newestFirst()
            .filter(ClarificationSummaryRecord.Columns.promptUuid == promptUuid)
            .select(ClarificationSummaryRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "clarification_summary",
            extra: [
                "prompt_uuid": promptUuid,
                "status": ClarificationStatus.building.rawValue,
            ]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid])
        )
        return (uuid, true)
    }

    // MARK: - Verbs

    /// Returns the clarification summary for a prompt, creating it if needed.
    /// - Parameter req: A request with the prompt uuid.
    /// - Returns: The clarification summary and a flag indicating whether it was newly created.
    /// - Throws: Errors from `ensureSummary` or when the summary cannot be fetched.
    func open(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: uuid)
        }
        return ClarifySummaryResponse(summary: summary, created: created)
    }

    /// Adds a question and optional answer choices to a clarification summary.
    /// - Parameter req: A request with the summary uuid, question text, and optional choice bodies.
    /// - Returns: The newly added question row.
    /// - Throws: Errors when the summary is not found, in an invalid state, or the request is malformed.
    func questionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        // building = the initial suite; answering = the generative
        // follow-up passes (the clarify_user instructions promise them).
        // Only complete refuses — reopen first.
        guard
            summary.clarificationStatus == .building
                || summary.clarificationStatus == .answering
        else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification",
                from: summary.status,
                to: "question-add",
                reason: "questions can be inserted while building or answering — reopen a complete summary first"
            )
        }
        let question = req.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw StoreError.badRequest(detail: "question is empty")
        }
        let seq =
            try nextSeq(
                db,
                in: UserClarificationQuestionRecord.self,
                parent: Column("clarification_summary_uuid"),
                uuid: req.summaryUuid
            ) + 1
        let uuid = try core.insertBase(
            db,
            table: "user_clarification_question",
            extra: [
                "clarification_summary_uuid": req.summaryUuid,
                "seq": seq,
                "question": question,
                "status": ClarificationRowStatus.open.rawValue,
                "agent_id": req.agentId,
                "agent_name": req.agentName.map(Store.normalizedAgentName),
            ]
        )
        for (i, body) in (req.options ?? []).enumerated() {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.badRequest(detail: "option \(i + 1) is empty")
            }
            try core.insertBase(
                db,
                table: "user_clarification_option",
                extra: [
                    "question_uuid": uuid,
                    "seq": i + 1,
                    "body": trimmed,
                ]
            )
        }
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "question_add", "seq": seq,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        guard let row = try fetchQuestion(uuid: uuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: uuid)
        }
        return ClarifyQuestionRowResponse(question: row)
    }

    /// Adds an internal note to a clarification summary.
    ///
    /// Notes are writable in any summary state — an agent may clarify its own
    /// confusion before sealing, while answering, or attach a note to an
    /// answered question after the fact.
    ///
    /// - Parameter req: A request with the summary uuid, note body, optional weight, and entity reference.
    /// - Returns: The newly added note row.
    /// - Throws: Errors when the summary is not found or the request is malformed.
    func noteAdd(_ req: ClarifyNoteAddRequest) throws -> ClarifyNoteRowResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        let body = req.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw StoreError.badRequest(detail: "note body is empty")
        }
        if let weight = req.weight {
            guard (0...999).contains(weight) else {
                throw StoreError.badRequest(
                    detail: "weight must be 0–999 (finding_rating polarity, 0 = critical)"
                )
            }
        }
        // CHECKless column, Swift-registry vocabulary (the post-m0021 rule).
        if let entityType = req.confusedEntityType {
            let legal = ["exploration_finding", "briefing", "question", "other"]
            guard legal.contains(entityType) else {
                throw StoreError.badRequest(
                    detail: "confused_entity_type must be one of \(legal.joined(separator: "|"))"
                )
            }
        }
        if let questionUuid = req.questionUuid {
            guard try UserClarificationQuestionRecord.exists(db, key: ["uuid": questionUuid]) else {
                throw StoreError.notFound(entity: "user_clarification_question", key: questionUuid)
            }
        }
        let uuid = try core.insertBase(
            db,
            table: "internal_clarification_note",
            extra: [
                "clarification_summary_uuid": req.summaryUuid,
                "body": body,
                "confused_entity_uuid": req.confusedEntityUuid,
                "confused_entity_type": req.confusedEntityType,
                "weight": req.weight,
                "question_uuid": req.questionUuid,
                "agent_id": req.agentId,
                "agent_name": req.agentName.map(Store.normalizedAgentName),
            ]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "note_add", "prompt_uuid": summary.promptUuid,
            ])
        )
        guard let row = try fetchNote(uuid: uuid) else {
            throw StoreError.notFound(entity: "internal_clarification_note", key: uuid)
        }
        return ClarifyNoteRowResponse(note: row)
    }

    /// Updates a question's answer status and content.
    ///
    /// Requires the summary at `answering` and never touches its version. A
    /// selection replaces junction rows wholesale; answered requires answer
    /// text or at least one option selection.
    ///
    /// - Parameter req: A request with the question uuid, answer text, selected option uuids, or skip flag.
    /// - Returns: The updated question row.
    /// - Throws: Errors when the question or summary is not found or in an invalid state.
    func answer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        guard let row = try fetchQuestion(uuid: req.questionUuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: req.questionUuid)
        }
        guard let summary = try fetchSummary(uuid: row.clarificationSummaryUuid),
            summary.clarificationStatus == .answering
        else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification",
                from: "summary",
                to: "answer",
                reason: "answers are writable only while the summary is answering (seal first, reopen after complete)"
            )
        }
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if req.skip {
            set["status"] = ClarificationRowStatus.skipped.rawValue
            // Wholesale symmetry with the answer branch: a skipped question
            // carries NO answer evidence, typed or selected.
            set["answer_text"] = nil as String?
            try db.execute(
                sql: "DELETE FROM user_clarification_answer WHERE question_uuid = ?",
                arguments: [req.questionUuid]
            )
        } else {
            let answerText = req.answerText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let selections = req.selectedOptionUuids ?? []
            guard !answerText.isEmpty || !selections.isEmpty else {
                throw StoreError.badRequest(
                    detail: "answer needs --answer text and/or --select option uuid(s) (or --skip)"
                )
            }
            let valid = try Set(
                UserClarificationOptionRecord
                    .all()
                    .filter(UserClarificationOptionRecord.Columns.questionUuid == req.questionUuid)
                    .select(UserClarificationOptionRecord.Columns.uuid, as: String.self)
                    .fetchAll(db)
            )
            for optionUuid in selections where !valid.contains(optionUuid) {
                throw StoreError.badRequest(
                    detail: "option \(optionUuid) does not belong to question \(req.questionUuid)"
                )
            }
            try db.execute(
                sql: "DELETE FROM user_clarification_answer WHERE question_uuid = ?",
                arguments: [req.questionUuid]
            )
            for optionUuid in selections {
                try core.insertBase(
                    db,
                    table: "user_clarification_answer",
                    extra: [
                        "question_uuid": req.questionUuid,
                        "option_uuid": optionUuid,
                    ]
                )
            }
            set["answer_text"] = answerText.isEmpty ? nil : answerText
            set["status"] = ClarificationRowStatus.answered.rawValue
        }
        try core.updateBase(
            db,
            table: "user_clarification_question",
            uuid: req.questionUuid,
            expectedVersion: req.expectedVersion,
            set: set
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: row.clarificationSummaryUuid,
            payload: Store.jsonPayload([
                "action": req.skip ? "skip" : "answer", "question_uuid": req.questionUuid,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        guard let updated = try fetchQuestion(uuid: req.questionUuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: req.questionUuid)
        }
        return ClarifyQuestionRowResponse(question: updated)
    }

    /// Moves a clarification from answering to complete (a pure gate).
    ///
    /// Every question must be answered or skipped; a care package, where one
    /// exists, must be ready. Writes nothing to the prompt row.
    ///
    /// - Parameter req: A request with the summary uuid and expected version.
    /// - Returns: The updated clarification summary.
    /// - Throws: Errors when the summary is not found, not answering, has open questions, or care package is not ready.
    func finalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        guard summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification",
                from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "finalize runs from answering"
            )
        }
        let openCount =
            try UserClarificationQuestionRecord
            .all()
            .filter(
                UserClarificationQuestionRecord.Columns.clarificationSummaryUuid == req.summaryUuid
            )
            .filter(
                UserClarificationQuestionRecord.Columns.status
                    == ClarificationRowStatus.open.rawValue
            )
            .fetchCount(db)
        guard openCount == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification",
                from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "\(openCount) question(s) still open — answer or skip them"
            )
        }
        // Variants whose phase graph includes the care package REQUIRE a
        // ready one at finalize — the clarified intent lives only there, and
        // sailing past finalize without it strands the architects.
        let package = try fetchPackage(bySummary: req.summaryUuid)
        let workflow = try BotWorkflowRepository(db: db, core: core)
            .fetchActive(promptUuid: summary.promptUuid)
        if let variantRaw = workflow?.variant,
            let variant = BotVariant(rawValue: variantRaw),
            WorkflowSpec.phases(for: variant).contains(.carePackage)
        {
            guard let package, package.status == "ready" else {
                throw StoreError.invalidEntityTransition(
                    entity: "clarification",
                    from: summary.status,
                    to: ClarificationStatus.complete.rawValue,
                    reason:
                        "the \(variantRaw) variant requires a READY care package before finalize — gm_hook call CARE_PACKAGE_OPEN, then care_ref_add, then care_package_complete first"
                )
            }
        } else if let package {
            guard package.status == "ready" else {
                throw StoreError.invalidEntityTransition(
                    entity: "clarification",
                    from: summary.status,
                    to: ClarificationStatus.complete.rawValue,
                    reason: "care package is still building — run care_package_complete first"
                )
            }
        }
        try core.updateBase(
            db,
            table: "clarification_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ClarificationStatus.complete.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "finalize", "prompt_uuid": summary.promptUuid])
        )
        try touchSessionForPrompt(promptUuid: summary.promptUuid)

        guard let updatedSummary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        return ClarifyFinalizeResponse(summary: updatedSummary)
    }

    /// Fetches the complete clarification state for a prompt.
    /// - Parameter req: A request with the prompt uuid and optional narrowing parameters.
    /// - Returns: A response containing the summary, questions, notes, and care package if present.
    /// - Throws: Errors when the prompt or summary is not found.
    func get(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // One request, eight statements: the summary with its questions,
        // options, answers, notes and care package refs.
        guard let root = try ClarificationWithChildren.request(promptUuid: req.promptUuid).fetchOne(db)
        else {
            // A6: the prompt EXISTS (guard above) — this absence is a
            // discriminated SUMMARY_ABSENT, not NOT_FOUND: open a summary.
            throw StoreError.summaryAbsent(
                entity: "clarification",
                promptUuid: req.promptUuid
            )
        }
        let summary = root.summary.dto()
        let package = root.carePackage?.dto()
        let questions = root.questions.map { $0.dto() }
        let allNotes = root.notes.map { $0.dto() }
        let staleness: CarePackageStaleness? = try package.map { pkg in
            let s = try dope.scopeStaleness(
                scopeUuid: pkg.dopeScopeUuid,
                stampedRevision: pkg.dopeScopeRevision,
                dotPaths: pkg.dopeRefs.map(\.dopeCode)
            )
            return CarePackageStaleness(
                stampedRevision: s.stamped,
                currentRevision: s.current,
                drifted: s.drifted,
                ghostDotPaths: s.ghosts
            )
        }

        // THE UNNARROWED REQUEST IS THE HISTORICAL RESPONSE, BYTE FOR BYTE —
        // no additive key emitted, so an older peer sees no change at all.
        guard req.isNarrowed else {
            return ClarifyGetResponse(
                summary: summary,
                questions: questions,
                notes: allNotes,
                carePackage: package,
                // INVARIANT: non-nil IFF carePackage is non-nil.
                carePackageStaleness: staleness
            )
        }

        // Weight window, mirroring the rating windows: an UNWEIGHTED note is
        // always full — the same rule that keeps unranked findings full in
        // EXPLORE_GET, because unrated is a work queue, not a low priority.
        let notes: [ClarificationNoteRow]
        let noteStubs: [ClarificationNoteStub]?
        if let ceiling = req.noteWeightMax {
            notes = allNotes.filter { ($0.weight ?? Int.min) <= ceiling }
            noteStubs =
                allNotes
                .filter { ($0.weight ?? Int.min) > ceiling }
                .map { note in
                    let body = CdeExcerpt.take(note.body)
                    return ClarificationNoteStub(
                        uuid: note.uuid,
                        weight: note.weight,
                        agentName: note.agentName,
                        questionUuid: note.questionUuid,
                        bodyExcerpt: body.excerpt,
                        bodyChars: body.chars,
                        bodyTruncated: body.truncated
                    )
                }
        } else {
            notes = allNotes
            noteStubs = nil
        }

        // Dropping the package keeps its EXISTENCE visible: carePackage nil
        // WITH a stub means narrowed away, carePackage nil WITHOUT one means
        // never opened. The staleness invariant holds either way — it rides
        // with the package it describes.
        let keepPackage = req.includeCarePackage ?? true
        return ClarifyGetResponse(
            summary: summary,
            questions: questions,
            notes: notes,
            carePackage: keepPackage ? package : nil,
            carePackageStaleness: keepPackage ? staleness : nil,
            carePackageStub: keepPackage ? nil : package.map(CarePackageStub.init(package:)),
            noteStubs: noteStubs
        )
    }

    // DELIBERATELY NOT DONE: no `staleness` on CarePackageResponse
    // (CARE_PACKAGE_GET). The CLI has no consumer today; it is a one-line
    // follow-up if `gm clarify package-get` ever wants a drift line.

    // MARK: - Care package verbs

    /// Returns the existing care package for a clarification or creates one.
    /// - Parameter req: A request with the clarification summary uuid.
    /// - Returns: The care package and a flag indicating whether it was newly created.
    /// - Throws: Errors when the summary is not found.
    func packageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        if let existing = try fetchPackage(bySummary: req.summaryUuid) {
            return CarePackageResponse(package: existing, created: false)
        }
        let uuid = try core.insertBase(
            db,
            table: "care_package",
            extra: [
                "clarification_summary_uuid": req.summaryUuid,
                "clarified_intent": "",
                "status": "building",
            ]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "package_open", "prompt_uuid": summary.promptUuid,
            ])
        )
        try touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let package = try fetchPackage(uuid: uuid) else {
            throw StoreError.notFound(entity: "care_package", key: uuid)
        }
        return CarePackageResponse(package: package, created: true)
    }

    /// Adds a reference (dope, kbite, or exploration) to a care package.
    /// - Parameter req: A request with the package uuid and reference details matching the kind.
    /// - Returns: The updated care package.
    /// - Throws: Errors when the package is not found, not building, or the request is malformed.
    func packageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        guard let package = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        guard package.status == "building" else {
            throw StoreError.invalidEntityTransition(
                entity: "care_package",
                from: package.status,
                to: "ref-add",
                reason: "refs can be added only while building"
            )
        }
        switch req.kind {
        case .dope:
            guard let code = req.dopeCode, !code.isEmpty else {
                throw StoreError.badRequest(detail: "kind dope requires --dope-code")
            }
            try core.insertBase(
                db,
                table: "care_package_dope_ref",
                extra: [
                    "care_package_uuid": req.packageUuid,
                    "dope_code": code,
                    "note": req.note,
                    "seq": try nextRefSeq(in: CarePackageDopeRefRecord.self, packageUuid: req.packageUuid),
                ]
            )
        case .kbite:
            guard let fileUuid = req.kbiteFileUuid, !fileUuid.isEmpty else {
                throw StoreError.badRequest(detail: "kind kbite requires --kbite-file-uuid")
            }
            // Denormalize the brief exactly like briefing complete does.
            guard
                let brief =
                    try KbiteResourceFileRecord
                    .all()
                    .withUuid(fileUuid)
                    .select(KbiteResourceFileRecord.Columns.resourceFileSummary, as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: "kbite_resource_file", key: fileUuid)
            }
            try core.insertBase(
                db,
                table: "care_package_kbite_ref",
                extra: [
                    "care_package_uuid": req.packageUuid,
                    "kbite_resource_file_uuid": fileUuid,
                    "brief": brief,
                    "seq": try nextRefSeq(in: CarePackageKbiteRefRecord.self, packageUuid: req.packageUuid),
                ]
            )
        case .exploration:
            guard let title = req.curatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                let body = req.curatedBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty, !body.isEmpty
            else {
                throw StoreError.badRequest(
                    detail: "kind exploration requires --title and --body (the curated COPY)"
                )
            }
            if let source = req.sourceFindingUuid {
                guard try ExplorationFindingRecord.exists(db, key: ["uuid": source]) else {
                    throw StoreError.notFound(entity: "exploration_finding", key: source)
                }
            }
            try core.insertBase(
                db,
                table: "care_package_exploration_ref",
                extra: [
                    "care_package_uuid": req.packageUuid,
                    "curated_title": title,
                    "curated_body": body,
                    "file_path": req.filePath,
                    "source_finding_uuid": req.sourceFindingUuid,
                    "seq": try nextRefSeq(
                        in: CarePackageExplorationRefRecord.self,
                        packageUuid: req.packageUuid
                    ),
                ]
            )
        }
        // Durable event + session touch like every sibling content verb —
        // GMVibes' care-package pane refreshes off the event stream.
        if let summary = try fetchSummary(uuid: package.clarificationSummaryUuid) {
            try core.appendEvent(
                db,
                kind: .clarificationChange,
                subjectUuid: req.packageUuid,
                payload: Store.jsonPayload([
                    "action": "package_ref_add", "kind": req.kind.rawValue,
                    "prompt_uuid": summary.promptUuid,
                ])
            )
            try touchSessionForPrompt(promptUuid: summary.promptUuid)
        }
        guard let updated = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        return CarePackageResponse(package: updated)
    }

    /// Moves a care package from building to ready.
    ///
    /// The clarified intent is carried only here; the daemon stamps the dope
    /// scope revision itself.
    ///
    /// - Parameter req: A request with the package uuid, clarified intent, and expected version.
    /// - Returns: The updated care package.
    /// - Throws: Errors when the package is not found or not building.
    func packageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        guard let package = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        guard package.status == "building" else {
            throw StoreError.invalidEntityTransition(
                entity: "care_package",
                from: package.status,
                to: "ready",
                reason: "package-complete runs from building"
            )
        }
        let intent = try Store.validatedOverview(req.clarifiedIntent, entity: "care_package")
        guard let summary = try fetchSummary(uuid: package.clarificationSummaryUuid) else {
            throw StoreError.notFound(
                entity: "clarification_summary",
                key: package.clarificationSummaryUuid
            )
        }
        guard let sessionUuid = try owningSession(promptUuid: summary.promptUuid) else {
            throw StoreError.notFound(entity: "prompt", key: summary.promptUuid)
        }
        let scope =
            try dope.dopeScopeCandidates(
                sessionUuid: sessionUuid,
                scopeType: .sessionInstance
            )
            .first
        try core.updateBase(
            db,
            table: "care_package",
            uuid: req.packageUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": "ready",
                "clarified_intent": intent,
                "dope_scope_uuid": scope?.uuid,
                "dope_scope_revision": scope?.revision,
            ]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: req.packageUuid,
            payload: Store.jsonPayload([
                "action": "package_complete", "prompt_uuid": summary.promptUuid,
                "dope_scope_revision": scope?.revision,
            ])
        )
        try touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        return CarePackageResponse(package: updated)
    }

    /// Fetches the care package for a prompt with optional narrowing.
    /// - Parameter req: A request with the prompt uuid and optional filtering parameters.
    /// - Returns: A response containing the care package and optionally stubs for narrowed references.
    /// - Throws: Errors when the prompt, summary, or care package is not found.
    func packageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            throw StoreError.summaryAbsent(entity: "clarification", promptUuid: req.promptUuid)
        }
        guard let package = try fetchPackage(bySummary: summary.uuid) else {
            throw StoreError.summaryAbsent(entity: "care_package", promptUuid: req.promptUuid)
        }
        // Unnarrowed = the historical response, byte for byte.
        guard req.isNarrowed else { return CarePackageResponse(package: package) }

        let wantEveryBody = req.includeRefBodies ?? (req.refUuid == nil)
        guard !wantEveryBody else { return CarePackageResponse(package: package) }

        // NARROWING EMPTIES AN ARRAY; IT NEVER REWRITES A ROW'S FIELDS. Every
        // CarePackageExplorationRefRow still carried below is verbatim — the
        // ones left out are named, in full, by the stub roster.
        let kept = req.refUuid.map { uuid in package.explorationRefs.filter { $0.uuid == uuid } } ?? []
        let stubs = package.explorationRefs.map { ref -> CarePackageExplorationRefStub in
            let body = CdeExcerpt.take(ref.curatedBody)
            return CarePackageExplorationRefStub(
                uuid: ref.uuid,
                curatedTitle: ref.curatedTitle,
                filePath: ref.filePath,
                sourceFindingUuid: ref.sourceFindingUuid,
                seq: ref.seq,
                curatedBodyExcerpt: body.excerpt,
                curatedBodyChars: body.chars,
                curatedBodyTruncated: body.truncated
            )
        }
        return CarePackageResponse(
            package: CarePackageRow(
                uuid: package.uuid,
                version: package.version,
                clarificationSummaryUuid: package.clarificationSummaryUuid,
                // The intent blob is the point of the package and is never
                // excerpted — see CarePackageGetRequest.
                clarifiedIntent: package.clarifiedIntent,
                status: package.status,
                dopeScopeUuid: package.dopeScopeUuid,
                dopeScopeRevision: package.dopeScopeRevision,
                dopeRefs: package.dopeRefs,
                kbiteRefs: package.kbiteRefs,
                explorationRefs: kept,
                createdAt: package.createdAt,
                updatedAt: package.updatedAt
            ),
            explorationRefStubs: stubs
        )
    }

    // MARK: - Shared transition + fetch helpers

    /// Moves a clarification summary to a new status after validation.
    /// - Parameters:
    ///   - summaryUuid: The clarification summary uuid.
    ///   - expectedVersion: The version the caller last read.
    ///   - to: The target status.
    ///   - action: The action name for event logging.
    ///   - requireFrom: The required current status.
    /// - Returns: The updated clarification summary.
    /// - Throws: Errors when the summary is not found or in an invalid state.
    func transition(
        summaryUuid: String,
        expectedVersion: Int64,
        to: ClarificationStatus,
        action: String,
        requireFrom: ClarificationStatus
    ) throws -> ClarifySummaryResponse {
        guard let summary = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: summaryUuid)
        }
        guard let from = summary.clarificationStatus else {
            throw StoreError.corruptState(entity: "clarification_summary", detail: "status '\(summary.status)'")
        }
        guard from == requireFrom, from.allowedNext.contains(to) else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification",
                from: from.rawValue,
                to: to.rawValue,
                reason: "\(action) runs from \(requireFrom.rawValue) — this summary is \(from.rawValue)"
            )
        }
        try core.updateBase(
            db,
            table: "clarification_summary",
            uuid: summaryUuid,
            expectedVersion: expectedVersion,
            set: ["status": to.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .clarificationChange,
            subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": action, "from": from.rawValue, "to": to.rawValue,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        guard let updated = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: summaryUuid)
        }
        return ClarifySummaryResponse(summary: updated)
    }

    /// Advances session recency without bumping the session version.
    ///
    /// Prompt-scoped writes use this to signal activity on the owning session.
    ///
    /// - Parameter promptUuid: The prompt uuid to find its session.
    /// - Throws: Database errors.
    func touchSessionForPrompt(promptUuid: String) throws {
        if let sessionUuid = try owningSession(promptUuid: promptUuid) {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    /// Fetches the session uuid for a prompt.
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The session uuid, or nil if the prompt does not exist.
    /// - Throws: Database errors.
    private func owningSession(promptUuid: String) throws -> String? {
        try PromptRecord
            .all()
            .withUuid(promptUuid)
            .select(PromptRecord.Columns.sessionUuid, as: String.self)
            .fetchOne(db)
    }

    /// Fetches a clarification summary by uuid.
    /// - Parameter uuid: The clarification summary uuid.
    /// - Returns: The summary row, or nil if not found.
    /// - Throws: Database errors.
    func fetchSummary(uuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(matching: ClarificationSummaryRecord.Columns.uuid == uuid)
    }

    /// Fetches a clarification summary by its associated prompt.
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The summary row, or nil if not found.
    /// - Throws: Database errors.
    func fetchSummary(byPrompt promptUuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(matching: ClarificationSummaryRecord.Columns.promptUuid == promptUuid)
    }

    /// Fetches a clarification summary matching a predicate.
    /// - Parameter predicate: An SQL expression to filter the summary.
    /// - Returns: The newest matching summary row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchSummary(matching predicate: SQLExpression) throws -> ClarificationSummaryRow? {
        try ClarificationSummaryRecord.all().newestFirst().filter(predicate).fetchOne(db)?.dto()
    }

    /// Fetches a clarification question by uuid.
    /// - Parameter uuid: The question uuid.
    /// - Returns: The question row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchQuestion(uuid: String) throws -> ClarificationQuestionRow? {
        try fetchQuestions(matching: UserClarificationQuestionRecord.Columns.uuid == uuid).first
    }

    /// Fetches all questions for a clarification summary.
    /// - Parameter summaryUuid: The clarification summary uuid.
    /// - Returns: An array of question rows in insertion order.
    /// - Throws: Database errors.
    func fetchQuestions(summaryUuid: String) throws -> [ClarificationQuestionRow] {
        try fetchQuestions(
            matching: UserClarificationQuestionRecord.Columns.clarificationSummaryUuid == summaryUuid
        )
    }

    /// Fetches questions matching a predicate with their options and selections.
    ///
    /// Three statements whatever the counts: questions, their options and
    /// their answer selections, all riding the composite's prefetches.
    ///
    /// - Parameter predicate: An SQL expression to filter the questions.
    /// - Returns: An array of question rows with options and selections populated.
    /// - Throws: Database errors.
    private func fetchQuestions(matching predicate: SQLExpression) throws -> [ClarificationQuestionRow] {
        try ClarificationQuestionWithOptions.request()
            .filter(predicate)
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches an internal note by uuid.
    /// - Parameter uuid: The note uuid.
    /// - Returns: The note row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchNote(uuid: String) throws -> ClarificationNoteRow? {
        try InternalClarificationNoteRecord.all().withUuid(uuid).fetchOne(db)?.dto()
    }

    /// Fetches all notes for a clarification summary, ordered by weight and id.
    /// - Parameter summaryUuid: The clarification summary uuid.
    /// - Returns: An array of note rows, sorted with critical notes first and unweighted notes last.
    /// - Throws: Database errors.
    func fetchNotes(summaryUuid: String) throws -> [ClarificationNoteRow] {
        // weight polarity: critical (low) first; unweighted last.
        try InternalClarificationNoteRecord
            .all()
            .filter(
                InternalClarificationNoteRecord.Columns.clarificationSummaryUuid == summaryUuid
            )
            .order(
                InternalClarificationNoteRecord.Columns.weight == nil,
                InternalClarificationNoteRecord.Columns.weight,
                Column("id")
            )
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches a care package by uuid with all its references.
    /// - Parameter uuid: The care package uuid.
    /// - Returns: The care package row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchPackage(uuid: String) throws -> CarePackageRow? {
        try CarePackageWithRefs.request()
            .filter(CarePackageRecord.Columns.uuid == uuid)
            .fetchOne(db)?
            .dto()
    }

    /// Fetches the care package for a clarification summary.
    /// - Parameter summaryUuid: The clarification summary uuid.
    /// - Returns: The care package row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchPackage(bySummary summaryUuid: String) throws -> CarePackageRow? {
        try CarePackageWithRefs.request()
            .filter(CarePackageRecord.Columns.clarificationSummaryUuid == summaryUuid)
            .fetchOne(db)?
            .dto()
    }

    /// Fetches the next sequence number for care package references of a given type.
    /// - Parameters:
    ///   - type: The reference record type (dope, kbite, or exploration).
    ///   - packageUuid: The care package uuid.
    /// - Returns: The next sequence number to use.
    /// - Throws: Database errors.
    private func nextRefSeq<T: TableRecord>(in type: T.Type, packageUuid: String) throws -> Int64 {
        try nextSeq(db, in: type, parent: Column("care_package_uuid"), uuid: packageUuid) + 1
    }
}
