import Foundation
import GRDB

/// CLARIFY_* / CARE_PACKAGE_* data access — the db-native clarification
/// machine. Runs INSIDE a Store-owned transaction; holds no dbQueue and
/// never self-transacts.
///
/// m0025 model: the summary is a slim status machine; questions
/// (user_clarification_question + option/answer children) and internal
/// notes are the content; the care package is the standalone clarified-
/// intent bundle. FINALIZE IS A PURE GATE — it never writes the prompt row
/// (the old refined_goal→prompt.goal copy is retired; prompt content is
/// human input only).
struct ClarificationRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Idempotent: returns the existing summary or creates one at `building`.
    /// Called by CLARIFY_OPEN and by setPromptStatus's draft → clarifying
    /// create-on-enter.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing = try String.fetchOne(
            db, sql: "SELECT uuid FROM clarification_summary WHERE prompt_uuid = ?",
            arguments: [promptUuid]
        ) {
            return (existing, false)
        }
        let uuid = try core.insertBase(db, table: "clarification_summary", extra: [
            "prompt_uuid": promptUuid,
            "status": ClarificationStatus.building.rawValue,
        ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid]))
        return (uuid, true)
    }

    // MARK: - Verbs

    func open(_ req: ClarifyOpenRequest) throws -> ClarifySummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: uuid)
        }
        return ClarifySummaryResponse(summary: summary, created: created)
    }

    func questionAdd(_ req: ClarifyQuestionAddRequest) throws -> ClarifyQuestionRowResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        // building = the initial suite; answering = the generative
        // follow-up passes (the clarify_user instructions promise them).
        // Only complete refuses — reopen first.
        guard summary.clarificationStatus == .building
            || summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status, to: "question-add",
                reason: "questions can be inserted while building or answering — reopen a complete summary first")
        }
        let question = req.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw StoreError.badRequest(detail: "question is empty")
        }
        let seq = (try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(seq), 0) FROM user_clarification_question WHERE clarification_summary_uuid = ?",
            arguments: [req.summaryUuid]) ?? 0) + 1
        let uuid = try core.insertBase(db, table: "user_clarification_question", extra: [
            "clarification_summary_uuid": req.summaryUuid,
            "seq": seq,
            "question": question,
            "status": ClarificationRowStatus.open.rawValue,
            "agent_id": req.agentId,
            "agent_name": req.agentName.map(Store.normalizedAgentName),
        ])
        for (i, body) in (req.options ?? []).enumerated() {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.badRequest(detail: "option \(i + 1) is empty")
            }
            try core.insertBase(db, table: "user_clarification_option", extra: [
                "question_uuid": uuid,
                "seq": i + 1,
                "body": trimmed,
            ])
        }
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "question_add", "seq": seq,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let row = try fetchQuestion(uuid: uuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: uuid)
        }
        return ClarifyQuestionRowResponse(question: row)
    }

    /// Notes are writable in ANY summary state — an agent may clarify its own
    /// confusion before sealing, while answering, or attach a note to an
    /// answered question after the fact.
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
                    detail: "weight must be 0–999 (finding_rating polarity, 0 = critical)")
            }
        }
        // CHECKless column, Swift-registry vocabulary (the post-m0021 rule).
        if let entityType = req.confusedEntityType {
            let legal = ["exploration_finding", "briefing", "question", "other"]
            guard legal.contains(entityType) else {
                throw StoreError.badRequest(
                    detail: "confused_entity_type must be one of \(legal.joined(separator: "|"))")
            }
        }
        if let questionUuid = req.questionUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM user_clarification_question WHERE uuid = ?",
                arguments: [questionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "user_clarification_question", key: questionUuid)
            }
        }
        let uuid = try core.insertBase(db, table: "internal_clarification_note", extra: [
            "clarification_summary_uuid": req.summaryUuid,
            "body": body,
            "confused_entity_uuid": req.confusedEntityUuid,
            "confused_entity_type": req.confusedEntityType,
            "weight": req.weight,
            "question_uuid": req.questionUuid,
            "agent_id": req.agentId,
            "agent_name": req.agentName.map(Store.normalizedAgentName),
        ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "note_add", "prompt_uuid": summary.promptUuid,
            ]))
        guard let row = try fetchNote(uuid: uuid) else {
            throw StoreError.notFound(entity: "internal_clarification_note", key: uuid)
        }
        return ClarifyNoteRowResponse(note: row)
    }

    /// Pure child-row update: requires the summary at `answering`, never
    /// touches its version. Revives a skipped row; skip=true marks skipped.
    /// A selection replaces the junction rows wholesale; answered requires
    /// answer_text OR at least one selection (Swift guard — no cross-table
    /// CHECK, the m0016 rule).
    func answer(_ req: ClarifyAnswerRequest) throws -> ClarifyQuestionRowResponse {
        guard let row = try fetchQuestion(uuid: req.questionUuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: req.questionUuid)
        }
        guard let summary = try fetchSummary(uuid: row.clarificationSummaryUuid),
              summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: "summary", to: "answer",
                reason: "answers are writable only while the summary is answering (seal first, reopen after complete)")
        }
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if req.skip {
            set["status"] = ClarificationRowStatus.skipped.rawValue
            // Wholesale symmetry with the answer branch: a skipped question
            // carries NO answer evidence, typed or selected.
            set["answer_text"] = nil as String?
            try db.execute(
                sql: "DELETE FROM user_clarification_answer WHERE question_uuid = ?",
                arguments: [req.questionUuid])
        } else {
            let answerText = req.answerText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let selections = req.selectedOptionUuids ?? []
            guard !answerText.isEmpty || !selections.isEmpty else {
                throw StoreError.badRequest(
                    detail: "answer needs --answer text and/or --select option uuid(s) (or --skip)")
            }
            let valid = try Set(String.fetchAll(
                db, sql: "SELECT uuid FROM user_clarification_option WHERE question_uuid = ?",
                arguments: [req.questionUuid]))
            for optionUuid in selections where !valid.contains(optionUuid) {
                throw StoreError.badRequest(
                    detail: "option \(optionUuid) does not belong to question \(req.questionUuid)")
            }
            try db.execute(
                sql: "DELETE FROM user_clarification_answer WHERE question_uuid = ?",
                arguments: [req.questionUuid])
            for optionUuid in selections {
                try core.insertBase(db, table: "user_clarification_answer", extra: [
                    "question_uuid": req.questionUuid,
                    "option_uuid": optionUuid,
                ])
            }
            set["answer_text"] = answerText.isEmpty ? nil : answerText
            set["status"] = ClarificationRowStatus.answered.rawValue
        }
        try core.updateBase(
            db, table: "user_clarification_question", uuid: req.questionUuid,
            expectedVersion: req.expectedVersion, set: set)
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: row.clarificationSummaryUuid,
            payload: Store.jsonPayload([
                "action": req.skip ? "skip" : "answer", "question_uuid": req.questionUuid,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let updated = try fetchQuestion(uuid: req.questionUuid) else {
            throw StoreError.notFound(entity: "user_clarification_question", key: req.questionUuid)
        }
        return ClarifyQuestionRowResponse(question: updated)
    }

    /// answering → complete — a PURE GATE. Every question answered or
    /// skipped; a care package, where one exists, must be ready. Writes
    /// NOTHING to the prompt row: the finalize→prompt.goal copy is retired
    /// (zero bot write doors to prompt content).
    func finalize(_ req: ClarifyFinalizeRequest) throws -> ClarifyFinalizeResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        guard summary.clarificationStatus == .answering else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "finalize runs from answering")
        }
        let openCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM user_clarification_question
            WHERE clarification_summary_uuid = ? AND status = 'open'
            """, arguments: [req.summaryUuid]) ?? 0
        guard openCount == 0 else {
            throw StoreError.invalidEntityTransition(
                entity: "clarification", from: summary.status,
                to: ClarificationStatus.complete.rawValue,
                reason: "\(openCount) question(s) still open — answer or skip them")
        }
        // Variants whose phase graph includes the care package REQUIRE a
        // ready one at finalize — the clarified intent lives only there, and
        // sailing past finalize without it strands the architects.
        let package = try fetchPackage(bySummary: req.summaryUuid)
        if let variantRaw = try String.fetchOne(
               db, sql: "SELECT variant FROM bot_workflow WHERE prompt_uuid = ? AND status = 'active'",
               arguments: [summary.promptUuid]),
           let variant = BotVariant(rawValue: variantRaw),
           WorkflowSpec.phases(for: variant).contains(.carePackage) {
            guard let package, package.status == "ready" else {
                throw StoreError.invalidEntityTransition(
                    entity: "clarification", from: summary.status,
                    to: ClarificationStatus.complete.rawValue,
                    reason: "the \(variantRaw) variant requires a READY care package before finalize — gmcc_hook call CARE_PACKAGE_OPEN, then care_ref_add, then care_package_complete first")
            }
        } else if let package {
            guard package.status == "ready" else {
                throw StoreError.invalidEntityTransition(
                    entity: "clarification", from: summary.status,
                    to: ClarificationStatus.complete.rawValue,
                    reason: "care package is still building — run care_package_complete first")
            }
        }
        try core.updateBase(
            db, table: "clarification_summary", uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": ClarificationStatus.complete.rawValue])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "finalize", "prompt_uuid": summary.promptUuid]))
        try touchSessionForPrompt(promptUuid: summary.promptUuid)

        guard let updatedSummary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        return ClarifyFinalizeResponse(summary: updatedSummary)
    }

    func get(_ req: ClarifyGetRequest) throws -> ClarifyGetResponse {
        guard try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        guard let summary = try fetchSummary(byPrompt: req.promptUuid) else {
            // A6: the prompt EXISTS (guard above) — this absence is a
            // discriminated SUMMARY_ABSENT, not NOT_FOUND: open a summary.
            throw StoreError.summaryAbsent(
                entity: "clarification", promptUuid: req.promptUuid)
        }
        let package = try fetchPackage(bySummary: summary.uuid)
        let questions = try fetchQuestions(summaryUuid: summary.uuid)
        let allNotes = try fetchNotes(summaryUuid: summary.uuid)
        let staleness: CarePackageStaleness? = try package.map { pkg in
            let s = try dope.scopeStaleness(
                scopeUuid: pkg.dopeScopeUuid,
                stampedRevision: pkg.dopeScopeRevision,
                dotPaths: pkg.dopeRefs.map(\.dopeCode))
            return CarePackageStaleness(
                stampedRevision: s.stamped,
                currentRevision: s.current,
                drifted: s.drifted,
                ghostDotPaths: s.ghosts)
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
                carePackageStaleness: staleness)
        }

        // Weight window, mirroring the rating windows: an UNWEIGHTED note is
        // always full — the same rule that keeps unranked findings full in
        // EXPLORE_GET, because unrated is a work queue, not a low priority.
        let notes: [ClarificationNoteRow]
        let noteStubs: [ClarificationNoteStub]?
        if let ceiling = req.noteWeightMax {
            notes = allNotes.filter { ($0.weight ?? Int.min) <= ceiling }
            noteStubs = allNotes
                .filter { ($0.weight ?? Int.min) > ceiling }
                .map { note in
                    let body = PenExcerpt.take(note.body)
                    return ClarificationNoteStub(
                        uuid: note.uuid,
                        weight: note.weight,
                        agentName: note.agentName,
                        questionUuid: note.questionUuid,
                        bodyExcerpt: body.excerpt,
                        bodyChars: body.chars,
                        bodyTruncated: body.truncated)
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
            noteStubs: noteStubs)
    }

    // DELIBERATELY NOT DONE: no `staleness` on CarePackageResponse
    // (CARE_PACKAGE_GET). The CLI has no consumer today; it is a one-line
    // follow-up if `gm clarify package-get` ever wants a drift line.

    // MARK: - Care package verbs

    func packageOpen(_ req: CarePackageOpenRequest) throws -> CarePackageResponse {
        guard let summary = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: req.summaryUuid)
        }
        if let existing = try fetchPackage(bySummary: req.summaryUuid) {
            return CarePackageResponse(package: existing, created: false)
        }
        let uuid = try core.insertBase(db, table: "care_package", extra: [
            "clarification_summary_uuid": req.summaryUuid,
            "clarified_intent": "",
            "status": "building",
        ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: uuid,
            payload: Store.jsonPayload([
                "action": "package_open", "prompt_uuid": summary.promptUuid,
            ]))
        try touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let package = try fetchPackage(uuid: uuid) else {
            throw StoreError.notFound(entity: "care_package", key: uuid)
        }
        return CarePackageResponse(package: package, created: true)
    }

    func packageRefAdd(_ req: CarePackageRefAddRequest) throws -> CarePackageResponse {
        guard let package = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        guard package.status == "building" else {
            throw StoreError.invalidEntityTransition(
                entity: "care_package", from: package.status, to: "ref-add",
                reason: "refs can be added only while building")
        }
        switch req.kind {
        case .dope:
            guard let code = req.dopeCode, !code.isEmpty else {
                throw StoreError.badRequest(detail: "kind dope requires --dope-code")
            }
            try core.insertBase(db, table: "care_package_dope_ref", extra: [
                "care_package_uuid": req.packageUuid,
                "dope_code": code,
                "note": req.note,
                "seq": try nextRefSeq(table: "care_package_dope_ref", packageUuid: req.packageUuid),
            ])
        case .kbite:
            guard let fileUuid = req.kbiteFileUuid, !fileUuid.isEmpty else {
                throw StoreError.badRequest(detail: "kind kbite requires --kbite-file-uuid")
            }
            // Denormalize the brief exactly like briefing complete does.
            guard let brief = try Row.fetchOne(
                db,
                sql: "SELECT resource_file_summary FROM kbite_resource_file WHERE uuid = ?",
                arguments: [fileUuid]
            ) else {
                throw StoreError.notFound(entity: "kbite_resource_file", key: fileUuid)
            }
            try core.insertBase(db, table: "care_package_kbite_ref", extra: [
                "care_package_uuid": req.packageUuid,
                "kbite_resource_file_uuid": fileUuid,
                "brief": brief["resource_file_summary"] as String?,
                "seq": try nextRefSeq(table: "care_package_kbite_ref", packageUuid: req.packageUuid),
            ])
        case .exploration:
            guard let title = req.curatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let body = req.curatedBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, !body.isEmpty else {
                throw StoreError.badRequest(
                    detail: "kind exploration requires --title and --body (the curated COPY)")
            }
            if let source = req.sourceFindingUuid {
                guard try Row.fetchOne(
                    db, sql: "SELECT 1 FROM exploration_finding WHERE uuid = ?", arguments: [source]
                ) != nil else {
                    throw StoreError.notFound(entity: "exploration_finding", key: source)
                }
            }
            try core.insertBase(db, table: "care_package_exploration_ref", extra: [
                "care_package_uuid": req.packageUuid,
                "curated_title": title,
                "curated_body": body,
                "file_path": req.filePath,
                "source_finding_uuid": req.sourceFindingUuid,
                "seq": try nextRefSeq(
                    table: "care_package_exploration_ref", packageUuid: req.packageUuid),
            ])
        }
        // Durable event + session touch like every sibling content verb —
        // GMVibes' care-package pane refreshes off the event stream.
        if let summary = try fetchSummary(uuid: package.clarificationSummaryUuid) {
            try core.appendEvent(
                db, kind: .clarificationChange, subjectUuid: req.packageUuid,
                payload: Store.jsonPayload([
                    "action": "package_ref_add", "kind": req.kind.rawValue,
                    "prompt_uuid": summary.promptUuid,
                ]))
            try touchSessionForPrompt(promptUuid: summary.promptUuid)
        }
        guard let updated = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        return CarePackageResponse(package: updated)
    }

    /// building → ready. clarifiedIntent is carried ONLY here; the daemon
    /// stamps the dope scope revision itself (briefing-complete idiom).
    func packageComplete(_ req: CarePackageCompleteRequest) throws -> CarePackageResponse {
        guard let package = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        guard package.status == "building" else {
            throw StoreError.invalidEntityTransition(
                entity: "care_package", from: package.status, to: "ready",
                reason: "package-complete runs from building")
        }
        let intent = try Store.validatedOverview(req.clarifiedIntent, entity: "care_package")
        guard let summary = try fetchSummary(uuid: package.clarificationSummaryUuid) else {
            throw StoreError.notFound(
                entity: "clarification_summary", key: package.clarificationSummaryUuid)
        }
        guard let sessionUuid = try String.fetchOne(
            db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?",
            arguments: [summary.promptUuid]
        ) else {
            throw StoreError.notFound(entity: "prompt", key: summary.promptUuid)
        }
        let scope = try dope.dopeScopeCandidates(
            sessionUuid: sessionUuid, scopeType: .sessionInstance
        ).first
        try core.updateBase(
            db, table: "care_package", uuid: req.packageUuid,
            expectedVersion: req.expectedVersion,
            set: [
                "status": "ready",
                "clarified_intent": intent,
                "dope_scope_uuid": scope?.uuid,
                "dope_scope_revision": scope?.revision,
            ])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: req.packageUuid,
            payload: Store.jsonPayload([
                "action": "package_complete", "prompt_uuid": summary.promptUuid,
                "dope_scope_revision": scope?.revision,
            ]))
        try touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchPackage(uuid: req.packageUuid) else {
            throw StoreError.notFound(entity: "care_package", key: req.packageUuid)
        }
        return CarePackageResponse(package: updated)
    }

    func packageGet(_ req: CarePackageGetRequest) throws -> CarePackageResponse {
        guard try Row.fetchOne(
            db, sql: "SELECT 1 FROM prompt WHERE uuid = ?", arguments: [req.promptUuid]
        ) != nil else {
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
            let body = PenExcerpt.take(ref.curatedBody)
            return CarePackageExplorationRefStub(
                uuid: ref.uuid,
                curatedTitle: ref.curatedTitle,
                filePath: ref.filePath,
                sourceFindingUuid: ref.sourceFindingUuid,
                seq: ref.seq,
                curatedBodyExcerpt: body.excerpt,
                curatedBodyChars: body.chars,
                curatedBodyTruncated: body.truncated)
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
                updatedAt: package.updatedAt),
            explorationRefStubs: stubs)
    }

    // MARK: - Shared transition + fetch helpers

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
                entity: "clarification", from: from.rawValue, to: to.rawValue,
                reason: "\(action) runs from \(requireFrom.rawValue) — this summary is \(from.rawValue)")
        }
        try core.updateBase(
            db, table: "clarification_summary", uuid: summaryUuid,
            expectedVersion: expectedVersion, set: ["status": to.rawValue])
        try core.appendEvent(
            db, kind: .clarificationChange, subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": action, "from": from.rawValue, "to": to.rawValue,
                "prompt_uuid": summary.promptUuid,
            ]))
        guard let updated = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "clarification_summary", key: summaryUuid)
        }
        return ClarifySummaryResponse(summary: updated)
    }

    /// Item 3 helper shared by the clarify/arch mutation paths: prompt-scoped
    /// writes advance session recency without bumping the session version.
    func touchSessionForPrompt(promptUuid: String) throws {
        if let sessionUuid = try String.fetchOne(
            db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?", arguments: [promptUuid]
        ) {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    func fetchSummary(uuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(where: "uuid = ?", key: uuid)
    }

    func fetchSummary(byPrompt promptUuid: String) throws -> ClarificationSummaryRow? {
        try fetchSummary(where: "prompt_uuid = ?", key: promptUuid)
    }

    private func fetchSummary(
        where condition: String, key: String
    ) throws -> ClarificationSummaryRow? {
        try ClarificationSummaryRecord.fetchAll(
            db, where: condition, arguments: [key]
        ).first?.wireRow()
    }

    private func fetchQuestion(uuid: String) throws -> ClarificationQuestionRow? {
        try fetchQuestions(where: "uuid = ?", key: uuid).first
    }

    func fetchQuestions(summaryUuid: String) throws -> [ClarificationQuestionRow] {
        try fetchQuestions(where: "clarification_summary_uuid = ?", key: summaryUuid)
    }

    private func fetchQuestions(
        where condition: String, key: String
    ) throws -> [ClarificationQuestionRow] {
        try UserClarificationQuestionRecord.fetchAll(
            db, where: condition, arguments: [key], orderBy: "seq"
        ).map { record in
            let options = try UserClarificationOptionRecord.fetchAll(
                db, where: "question_uuid = ?", arguments: [record.uuid], orderBy: "seq"
            ).map { $0.wireRow() }
            let selected = try String.fetchAll(
                db,
                sql: "SELECT option_uuid FROM user_clarification_answer WHERE question_uuid = ? ORDER BY id",
                arguments: [record.uuid])
            return record.wireRow(options: options, selectedOptionUuids: selected)
        }
    }

    private func fetchNote(uuid: String) throws -> ClarificationNoteRow? {
        try InternalClarificationNoteRecord.fetchAll(
            db, where: "uuid = ?", arguments: [uuid]
        ).first?.wireRow()
    }

    func fetchNotes(summaryUuid: String) throws -> [ClarificationNoteRow] {
        // weight polarity: critical (low) first; unweighted last.
        try InternalClarificationNoteRecord.fetchAll(
            db, where: "clarification_summary_uuid = ?", arguments: [summaryUuid],
            orderBy: "weight IS NULL, weight, id"
        ).map { $0.wireRow() }
    }

    private func fetchPackage(uuid: String) throws -> CarePackageRow? {
        try CarePackageRecord.fetchAll(
            db, where: "uuid = ?", arguments: [uuid]
        ).first.map(assemblePackage)
    }

    private func fetchPackage(bySummary summaryUuid: String) throws -> CarePackageRow? {
        try CarePackageRecord.fetchAll(
            db, where: "clarification_summary_uuid = ?", arguments: [summaryUuid]
        ).first.map(assemblePackage)
    }

    private func assemblePackage(_ record: CarePackageRecord) throws -> CarePackageRow {
        let dopeRefs = try CarePackageDopeRefRecord.fetchAll(
            db, where: "care_package_uuid = ?", arguments: [record.uuid], orderBy: "seq"
        ).map { $0.wireRow() }
        let kbiteRefs = try CarePackageKbiteRefRecord.fetchAll(
            db, where: "care_package_uuid = ?", arguments: [record.uuid], orderBy: "seq"
        ).map { $0.wireRow() }
        let explorationRefs = try CarePackageExplorationRefRecord.fetchAll(
            db, where: "care_package_uuid = ?", arguments: [record.uuid], orderBy: "seq"
        ).map { $0.wireRow() }
        return record.wireRow(
            dopeRefs: dopeRefs, kbiteRefs: kbiteRefs, explorationRefs: explorationRefs)
    }

    private func nextRefSeq(table: String, packageUuid: String) throws -> Int64 {
        (try Int64.fetchOne(
            db, sql: "SELECT COALESCE(MAX(seq), 0) FROM \(table) WHERE care_package_uuid = ?",
            arguments: [packageUuid]) ?? 0) + 1
    }
}
