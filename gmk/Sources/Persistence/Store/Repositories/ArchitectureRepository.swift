import Foundation
import GRDB

/// ARCH_* data access — the db-native architecture machine.
///
/// Runs INSIDE a Store-owned transaction; holds no dbQueue and never
/// self-transacts.
struct ArchitectureRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Shared create-or-return

    /// Creates or returns the architecture summary for a prompt.
    ///
    /// Idempotent create-or-return called by ARCH_OPEN and by
    /// setPromptStatus's clarifying → architecting create-on-enter flow.
    ///
    /// - Parameter promptUuid: The prompt uuid; must exist in the database.
    /// - Returns: The summary uuid and whether it was newly created.
    /// - Throws: `StoreError.notFound` when the prompt does not exist.
    @discardableResult
    func ensureSummary(promptUuid: String) throws -> (uuid: String, created: Bool) {
        guard try PromptRecord.exists(db, key: ["uuid": promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: promptUuid)
        }
        if let existing =
            try ArchitectureSummaryRecord
            .all()
            .newestFirst()
            .filter(ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
            .select(ArchitectureSummaryRecord.Columns.uuid, as: String.self)
            .fetchOne(db)
        {
            return (existing, false)
        }
        let uuid = try core.insertBase(
            db,
            table: "architecture_summary",
            extra: [
                "prompt_uuid": promptUuid,
                "body": "",
                "status": ArchitectureStatus.drafting.rawValue,
            ]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: uuid,
            payload: Store.jsonPayload(["action": "open", "prompt_uuid": promptUuid])
        )
        return (uuid, true)
    }

    // MARK: - Verbs

    /// Opens an architecture summary, creating one if it does not exist.
    ///
    /// - Parameter req: The open request carrying the prompt uuid.
    /// - Returns: The summary row and whether it was newly created.
    /// - Throws: `StoreError.notFound` when the prompt does not exist.
    func open(_ req: ArchOpenRequest) throws -> ArchSummaryResponse {
        let (uuid, created) = try ensureSummary(promptUuid: req.promptUuid)
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: uuid)
        }
        return ArchSummaryResponse(summary: summary, created: created)
    }

    /// Writes the summary body and records the change.
    ///
    /// - Parameter req: The summarize request with summary uuid, body, and expected version.
    /// - Returns: The updated summary row.
    /// - Throws: `StoreError.versionConflict` on a stale expected version.
    func summarize(_ req: ArchSummarizeRequest) throws -> ArchSummaryResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "summarize")
        try core.updateBase(
            db,
            table: "architecture_summary",
            uuid: req.summaryUuid,
            expectedVersion: req.expectedVersion,
            set: ["body": req.body]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload(["action": "summarize", "prompt_uuid": summary.promptUuid])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: req.summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: req.summaryUuid)
        }
        return ArchSummaryResponse(summary: updated)
    }

    /// Adds a persistence change row to the architecture summary.
    ///
    /// - Parameter req: The request with summary uuid, class name, file path, and change metadata.
    /// - Returns: The created persistence change row.
    /// - Throws: `StoreError` variants for invalid state or conflicts.
    func persistAdd(_ req: ArchPersistAddRequest) throws -> ArchPersistAddResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "persist-add")
        try requireDecisionBeforeExpansion(summaryUuid: req.summaryUuid, verb: "persist-add")
        let changeKind = try validatedChangeKind(req.changeKind, defaulting: "modify")
        let path = try Store.normalizeRepoRelativePath(
            req.filePath,
            repoRoot: try instanceRoot(promptUuid: summary.promptUuid)
        )
        let seq =
            try nextSeq(
                db,
                in: ArchitecturePersistenceChangeRecord.self,
                parent: Column("architecture_summary_uuid"),
                uuid: req.summaryUuid
            ) + 1
        let uuid = try core.insertBase(
            db,
            table: "architecture_persistence_change",
            extra: [
                "architecture_summary_uuid": req.summaryUuid,
                "seq": seq,
                "class_name": req.className,
                "file_path": path,
                "reason_brief": req.reasonBrief,
                "change_kind": changeKind,
                "dope_ref": req.dopeRef,
            ]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "persist_add", "seq": seq, "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        let touched = try touchedPaths(promptUuid: summary.promptUuid)
        guard
            let change = try fetchPersistenceChanges(
                summaryUuid: req.summaryUuid,
                touched: touched
            )
            .first(where: { $0.uuid == uuid })
        else {
            throw StoreError.notFound(entity: "architecture_persistence_change", key: uuid)
        }
        return ArchPersistAddResponse(change: change)
    }

    /// Adds a field change to a persistence change row.
    ///
    /// - Parameter req: The request with persistence change uuid, field name, and metadata.
    /// - Returns: The created field change row.
    /// - Throws: `StoreError` variants for invalid state or conflicts.
    func fieldAdd(_ req: ArchFieldAddRequest) throws -> ArchFieldAddResponse {
        let summaryUuid = try parentSummaryUuid(persistenceChangeUuid: req.persistenceChangeUuid)
        let summary = try requireSummary(uuid: summaryUuid, at: .drafting, verb: "field-add")
        try requireDecisionBeforeExpansion(summaryUuid: summaryUuid, verb: "field-add")
        let changeKind = try validatedChangeKind(req.changeKind, defaulting: "add")
        if req.isForeignKey, (req.fkTarget ?? "").isEmpty {
            throw StoreError.badRequest(detail: "--fk-target is required with --foreign-key")
        }
        if changeKind == "rename", (req.renamedFrom ?? "").isEmpty {
            throw StoreError.badRequest(detail: "--renamed-from is required with --change-kind rename")
        }
        let seq =
            try nextSeq(
                db,
                in: ArchitecturePersistenceFieldChangeRecord.self,
                parent: Column("persistence_change_uuid"),
                uuid: req.persistenceChangeUuid
            ) + 1
        let uuid = try core.insertBase(
            db,
            table: "architecture_persistence_field_change",
            extra: [
                "persistence_change_uuid": req.persistenceChangeUuid,
                "seq": seq,
                "field_name": req.fieldName,
                "change_reason": req.changeReason,
                "change_purpose": req.changePurpose,
                "data_type": req.dataType,
                "nullable": req.nullable ? 1 : 0,
                "is_foreign_key": req.isForeignKey ? 1 : 0,
                "fk_target": req.isForeignKey ? req.fkTarget : nil,
                "is_indexed": req.isIndexed ? 1 : 0,
                "change_kind": changeKind,
                "renamed_from": req.renamedFrom,
                "dope_property_ref": req.dopePropertyRef,
            ]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": "field_add", "persistence_change_uuid": req.persistenceChangeUuid,
                "field_name": req.fieldName,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        guard
            let field = try fetchFieldChanges(changeUuid: req.persistenceChangeUuid)
                .first(where: { $0.uuid == uuid })
        else {
            throw StoreError.notFound(entity: "architecture_persistence_field_change", key: uuid)
        }
        return ArchFieldAddResponse(field: field)
    }

    /// Adds a general change row to the architecture summary.
    ///
    /// - Parameter req: The request with summary uuid, file path, class name, and change code.
    /// - Returns: The created general change row.
    /// - Throws: `StoreError` variants for invalid state or conflicts.
    func generalAdd(_ req: ArchGeneralAddRequest) throws -> ArchGeneralAddResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "general-add")
        try requireDecisionBeforeExpansion(summaryUuid: req.summaryUuid, verb: "general-add")
        guard req.changeCode.utf8.count <= Store.maxChangeCodeBytes else {
            throw StoreError.badRequest(
                detail: "change_code exceeds \(Store.maxChangeCodeBytes / (1024 * 1024)) MB"
            )
        }
        let path = try Store.normalizeRepoRelativePath(
            req.filePath,
            repoRoot: try instanceRoot(promptUuid: summary.promptUuid)
        )
        let seq =
            try nextSeq(
                db,
                in: ArchitectureGeneralChangeRecord.self,
                parent: Column("architecture_summary_uuid"),
                uuid: req.summaryUuid
            ) + 1
        let uuid = try core.insertBase(
            db,
            table: "architecture_general_change",
            extra: [
                "architecture_summary_uuid": req.summaryUuid,
                "seq": seq,
                "file_path": path,
                "class_name": req.className,
                "reason_brief": req.reasonBrief,
                "change_depth": req.changeDepth.rawValue,
                "change_code": req.changeCode,
            ]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": "general_add", "seq": seq, "file_path": path,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        let touched = try touchedPaths(promptUuid: summary.promptUuid)
        guard
            let change = try fetchGeneralChanges(
                summaryUuid: req.summaryUuid,
                touched: touched
            )
            .first(where: { $0.uuid == uuid })
        else {
            throw StoreError.notFound(entity: "architecture_general_change", key: uuid)
        }
        return ArchGeneralAddResponse(change: change)
    }

    // MARK: - Options

    /// Adds or revises an architecture option for one agent.
    ///
    /// One option row per agent per summary with UNIQUE(summary, agent_name);
    /// re-add by the same agent is refused because the option IS the proposal.
    /// Pass `supersedes_option_uuid` + `expected_version` to replace an existing
    /// option atomically. The superseded row is stamped `rejected` but kept,
    /// and its selection carries over with a note appended to the summary's
    /// rationale so the selection never vanishes mid-drafting.
    ///
    /// - Parameter req: The request with summary uuid, agent name and id, body, and optional supersession.
    /// - Returns: The created or superseding option row.
    /// - Throws: `StoreError` variants for invalid state or conflicts.
    func optionAdd(_ req: ArchOptionAddRequest) throws -> ArchOptionRowResponse {
        let summary = try requireSummary(uuid: req.summaryUuid, at: .drafting, verb: "option-add")
        let agentName = Store.normalizedAgentName(req.agentName)
        guard !agentName.isEmpty else {
            throw StoreError.badRequest(detail: "agent_name is empty")
        }
        let body = try validatedOptionBody(req.body)
        let superseded = try supersededOption(req)
        try refuseOptionCollision(
            summaryUuid: req.summaryUuid,
            agentName: agentName,
            excluding: superseded?.uuid
        )
        // Insert first, then reject: a failure between the two rolls the whole
        // verb back (one boundary), so no state exists where the old row is
        // rejected and no successor landed.
        let wasSelected = superseded?.status == "selected"
        let uuid = try core.insertBase(
            db,
            table: "architecture_option",
            extra: [
                "architecture_summary_uuid": req.summaryUuid,
                "agent_name": agentName,
                "agent_id": req.agentId,
                "body": body,
                "status": wasSelected ? "selected" : "proposed",
            ]
        )
        if let superseded {
            try core.updateBase(
                db,
                table: "architecture_option",
                uuid: superseded.uuid,
                expectedVersion: req.expectedVersion!,
                set: ["status": "rejected"]
            )
            if wasSelected {
                try carryOverSelection(
                    summaryUuid: req.summaryUuid,
                    from: superseded.uuid,
                    to: uuid
                )
            }
        }
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: req.summaryUuid,
            payload: Store.jsonPayload([
                "action": superseded == nil ? "option_add" : "option_supersede",
                "agent_name": agentName,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let row = try fetchOption(uuid: uuid) else {
            throw StoreError.notFound(entity: "architecture_option", key: uuid)
        }
        return ArchOptionRowResponse(option: row)
    }

    /// Trims an option body and refuses it when empty or over the narrative size cap.
    ///
    /// - Parameter raw: The option body as sent.
    /// - Returns: The trimmed body.
    /// - Throws: `StoreError.badRequest` when the body is empty or too large.
    private func validatedOptionBody(_ raw: String) throws -> String {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw StoreError.badRequest(detail: "option body is empty")
        }
        guard body.utf8.count <= Store.maxNarrativeBytes else {
            throw StoreError.badRequest(
                detail: "option body exceeds \(Store.maxNarrativeBytes / (1024 * 1024)) MB"
            )
        }
        return body
    }

    /// Resolves the option an option-add supersedes, if any.
    ///
    /// - Parameter req: The option-add request carrying the optional supersede pair.
    /// - Returns: The superseded option row, or nil when the request supersedes nothing.
    /// - Throws: `StoreError.badRequest` on a half pair or foreign summary, `notFound` when absent.
    private func supersededOption(_ req: ArchOptionAddRequest) throws -> ArchitectureOptionRow? {
        // The supersede pair travels together — one without the other is a
        // caller mistake, refused before anything is written.
        if (req.supersedesOptionUuid == nil) != (req.expectedVersion == nil) {
            throw StoreError.badRequest(
                detail: "supersedes_option_uuid and expected_version must be passed together"
            )
        }
        var superseded: ArchitectureOptionRow?
        if let supersedesUuid = req.supersedesOptionUuid {
            guard let old = try fetchOption(uuid: supersedesUuid) else {
                throw StoreError.notFound(entity: "architecture_option", key: supersedesUuid)
            }
            guard old.architectureSummaryUuid == req.summaryUuid else {
                throw StoreError.badRequest(
                    detail: "option \(supersedesUuid) belongs to a different summary"
                )
            }
            superseded = old
        }
        return superseded
    }

    /// Refuses an option-add when the agent already holds another option on the summary.
    ///
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - agentName: The normalized agent name.
    ///   - excluding: The superseded option uuid, which does not count as a collision.
    /// - Throws: `StoreError.badRequest` when a live option by the same agent exists.
    private func refuseOptionCollision(
        summaryUuid: String,
        agentName: String,
        excluding: String?
    ) throws {
        let collisions =
            try ArchitectureOptionRecord
            .all()
            .filter(ArchitectureOptionRecord.Columns.architectureSummaryUuid == summaryUuid)
            .filter(ArchitectureOptionRecord.Columns.agentName == agentName)
            .filter(ArchitectureOptionRecord.Columns.uuid != (excluding ?? ""))
            .fetchCount(db)
        if collisions > 0 {
            // A persona may replace ITS OWN proposal (the superseded row is
            // excluded above); colliding with a live sibling persona is still
            // refused.
            throw StoreError.badRequest(
                detail: "agent '\(agentName)' already wrote an option for this summary"
            )
        }
    }

    /// Carries a superseded selection to its successor option.
    ///
    /// When an option with a selection is superseded, the selection rides over
    /// to the new option with the move appended to the summary's rationale so
    /// both rows stay in the record.
    ///
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - from: The superseded option uuid.
    ///   - to: The new option uuid that carries the selection.
    /// - Throws: `StoreError.versionConflict` on version conflicts.
    private func carryOverSelection(summaryUuid: String, from: String, to: String) throws {
        let version = try summaryVersion(uuid: summaryUuid)
        let existing =
            try ArchitectureSummaryRecord
            .all()
            .withUuid(summaryUuid)
            .select(ArchitectureSummaryRecord.Columns.decisionRationale, as: String.self)
            .fetchOne(db) ?? ""
        let stamp = "revised \(StoreCore.isoNow()): option \(from) superseded by \(to)"
        try core.updateBase(
            db,
            table: "architecture_summary",
            uuid: summaryUuid,
            expectedVersion: version,
            set: ["decision_rationale": existing.isEmpty ? stamp : existing + "\n" + stamp]
        )
    }

    /// Selects one option, rejects its siblings, and records the rationale.
    ///
    /// Atomically stamps the selected option as chosen, rejects all sibling
    /// options, and records the decision rationale on the summary. The
    /// `expectedVersion` targets the selected option row, not the summary.
    ///
    /// - Parameter req: The request with option uuid, expected version, and rationale.
    /// - Returns: The updated summary and all options.
    /// - Throws: `StoreError` variants for invalid state or version conflicts.
    func decide(_ req: ArchDecideRequest) throws -> ArchDecideResponse {
        guard let winner = try fetchOption(uuid: req.optionUuid) else {
            throw StoreError.notFound(entity: "architecture_option", key: req.optionUuid)
        }
        let summary = try requireSummary(
            uuid: winner.architectureSummaryUuid,
            at: .drafting,
            verb: "decide"
        )
        let rationale = req.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rationale.isEmpty else {
            throw StoreError.badRequest(detail: "decision rationale is empty")
        }
        try core.updateBase(
            db,
            table: "architecture_option",
            uuid: req.optionUuid,
            expectedVersion: req.expectedVersion,
            set: ["status": "selected"]
        )
        let siblings = try fetchOptions(
            matching: ArchitectureOptionRecord.Columns.architectureSummaryUuid
                == winner.architectureSummaryUuid
                && ArchitectureOptionRecord.Columns.uuid != req.optionUuid
        )
        for sibling in siblings {
            try core.updateBase(
                db,
                table: "architecture_option",
                uuid: sibling.uuid,
                expectedVersion: sibling.version,
                set: ["status": "rejected"]
            )
        }
        try core.updateBase(
            db,
            table: "architecture_summary",
            uuid: winner.architectureSummaryUuid,
            expectedVersion: try summaryVersion(uuid: winner.architectureSummaryUuid),
            set: ["decision_rationale": rationale]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: winner.architectureSummaryUuid,
            payload: Store.jsonPayload([
                "action": "decide", "selected_option": req.optionUuid,
                "agent_name": winner.agentName, "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updatedSummary = try fetchSummary(uuid: winner.architectureSummaryUuid) else {
            throw StoreError.notFound(
                entity: "architecture_summary",
                key: winner.architectureSummaryUuid
            )
        }
        return ArchDecideResponse(
            summary: updatedSummary,
            options: try fetchOptions(summaryUuid: winner.architectureSummaryUuid)
        )
    }

    /// Fetches the architecture state for a prompt.
    ///
    /// Returns the summary, all persistence and general changes, options,
    /// and unplanned file paths. Narrows the result by option uuid or change
    /// uuid if requested, returning stubs and excerpts to fit the response size.
    ///
    /// - Parameter req: The request with prompt uuid and optional narrowing.
    /// - Returns: The architecture state, possibly narrowed and paged.
    /// - Throws: `StoreError` variants for missing prompts or summaries.
    func get(_ req: ArchGetRequest) throws -> ArchGetResponse {
        guard try PromptRecord.exists(db, key: ["uuid": req.promptUuid]) else {
            throw StoreError.notFound(entity: "prompt", key: req.promptUuid)
        }
        // One request, five statements: the summary with its persistence
        // changes, their fields, its general changes and its options.
        guard let root = try ArchitectureWithChanges.request(promptUuid: req.promptUuid).fetchOne(db)
        else {
            // A6: prompt exists — discriminated SUMMARY_ABSENT (gm arch open).
            throw StoreError.summaryAbsent(
                entity: "architecture",
                promptUuid: req.promptUuid
            )
        }
        let summary = root.summary.dto()
        let touched = try touchedPaths(promptUuid: req.promptUuid)
        // PERSISTENCE IS NEVER NARROWED AND NEVER PAGED. It is the
        // persistence-first contract, and it is what a clipped response ate
        // silently — so it comes back whole in every form of this response.
        // The general set is UNPAGED too. Every derived verdict below is
        // computed from it, so asking for one page can never change an audit answer.
        let (persistence, allGeneral) = plannedChanges(of: root, touched: touched)

        // Scope drift: this prompt's touched paths absent from the plan.
        let plannedPaths = Set(persistence.map(\.filePath) + allGeneral.map(\.filePath))
        let unplanned = touched.values
            .filter { !plannedPaths.contains($0.path) }
            .sorted { $0.path < $1.path }

        let orderingRespected = persistenceFirstRespected(persistence: persistence, general: allGeneral)

        let allOptions = root.options.map { $0.dto() }

        // THE UNNARROWED REQUEST IS THE HISTORICAL RESPONSE, BYTE FOR BYTE.
        // No new key is emitted at all, so a peer built against the old
        // package (GMVibes) is unchanged by construction — which is why the
        // narrowing fields are additive optionals and the wire did not bump.
        guard req.isNarrowed else {
            return ArchGetResponse(
                summary: summary,
                persistenceChanges: persistence,
                generalChanges: allGeneral,
                unplannedChanges: unplanned,
                orderingRespected: orderingRespected,
                options: allOptions
            )
        }

        // An explicit includeOptions/full wins; otherwise naming ONE uuid
        // means "that one body, and nothing else's".
        let wantEveryOptionBody = req.includeOptions ?? (req.optionUuid == nil)
        let wantEveryChangeCode = req.full ?? (req.changeUuid == nil)

        let (options, optionStubs) = narrowOptions(
            allOptions,
            optionUuid: req.optionUuid,
            wantEveryBody: wantEveryOptionBody
        )
        let (window, nextCursor) = try pageGeneralChanges(allGeneral, req: req)
        let (generalChanges, generalChangeStubs) = projectGeneralChanges(
            window: window,
            allGeneral: allGeneral,
            changeUuid: req.changeUuid,
            wantEveryCode: wantEveryChangeCode
        )

        return ArchGetResponse(
            summary: summary,
            persistenceChanges: persistence,
            generalChanges: generalChanges,
            unplannedChanges: unplanned,
            orderingRespected: orderingRespected,
            options: options,
            optionStubs: optionStubs,
            generalChangeStubs: generalChangeStubs,
            changePage: ArchChangePage(
                limit: req.limit,
                returned: window.count,
                totalGeneralChanges: allGeneral.count,
                nextCursor: nextCursor
            )
        )
    }

    /// Audits that every persistence path was first touched before any general path.
    ///
    /// - Parameters:
    ///   - persistence: The planned persistence changes with their implementation state.
    ///   - general: The planned general changes with their implementation state.
    /// - Returns: The audit verdict, nil when either side is empty or untouched.
    private func persistenceFirstRespected(
        persistence: [ArchPersistenceChangeRow],
        general: [ArchGeneralChangeRow]
    ) -> Bool? {
        // Persistence-first audit: every persistence path's first touch
        // must precede every general path's first touch. Vacuously nil
        // when either side is empty or untouched.
        let persistenceFirsts = persistence.compactMap(\.implementation.firstChangedAt)
        let generalFirsts = general.compactMap(\.implementation.firstChangedAt)
        let orderingRespected: Bool?
        if let latestPersistence = persistenceFirsts.max(), let earliestGeneral = generalFirsts.min() {
            orderingRespected = latestPersistence <= earliestGeneral
        } else {
            orderingRespected = nil
        }
        return orderingRespected
    }

    /// Narrows the option set to the named body while keeping a stub for every option.
    ///
    /// - Parameters:
    ///   - allOptions: Every option row of the summary.
    ///   - optionUuid: The one option whose body is wanted, if named.
    ///   - wantEveryBody: True to return every body and no stubs.
    /// - Returns: The full option rows and the stub roster, nil when every body is returned.
    private func narrowOptions(
        _ allOptions: [ArchitectureOptionRow],
        optionUuid: String?,
        wantEveryBody: Bool
    ) -> (options: [ArchitectureOptionRow], stubs: [ArchitectureOptionStub]?) {
        let options: [ArchitectureOptionRow]
        let optionStubs: [ArchitectureOptionStub]?
        if wantEveryBody {
            options = allOptions
            optionStubs = nil
        } else {
            options = optionUuid.map { uuid in allOptions.filter { $0.uuid == uuid } } ?? []
            // The ROSTER is always complete: a body can be withheld, an
            // option's existence cannot.
            optionStubs = allOptions.map { option in
                ArchitectureOptionStub(
                    uuid: option.uuid,
                    agentName: option.agentName,
                    agentId: option.agentId,
                    status: option.status,
                    selected: option.status == "selected",
                    bodyChars: option.body.count
                )
            }
        }
        return (options, optionStubs)
    }

    /// Cuts the general-change page selected by the request's cursor and limit.
    ///
    /// - Parameters:
    ///   - allGeneral: Every general change of the summary, in seq order.
    ///   - req: The get request carrying cursor, limit and change uuid.
    /// - Returns: The page window and the cursor of the next page, nil on the last page.
    /// - Throws: `StoreError.badRequest` on a non-numeric cursor or a non-positive limit.
    private func pageGeneralChanges(
        _ allGeneral: [ArchGeneralChangeRow],
        req: ArchGetRequest
    ) throws -> (window: [ArchGeneralChangeRow], nextCursor: String?) {
        // changeUuid pins one row by identity, so it ignores limit/cursor —
        // "give me this" is not a page.
        var window = allGeneral
        var nextCursor: String?
        if req.changeUuid == nil {
            if let cursor = req.cursor {
                guard let afterSeq = Int64(cursor) else {
                    throw StoreError.badRequest(
                        detail: "cursor must be a change_page.next_cursor value (got '\(cursor)')"
                    )
                }
                window = window.filter { $0.seq > afterSeq }
            }
            if let limit = req.limit {
                guard limit > 0 else {
                    throw StoreError.badRequest(detail: "limit must be positive (got \(limit))")
                }
                if window.count > limit {
                    nextCursor = String(window[limit - 1].seq)
                    window = Array(window.prefix(limit))
                }
            }
        }
        return (window, nextCursor)
    }

    /// Projects the paged general changes into full rows or excerpted stubs.
    ///
    /// - Parameters:
    ///   - window: The paged general changes.
    ///   - allGeneral: Every general change of the summary, searched for the pinned uuid.
    ///   - changeUuid: The one change whose code is wanted, if named.
    ///   - wantEveryCode: True to return the window whole and no stubs.
    /// - Returns: The full change rows and the stubs, nil when every code is returned.
    private func projectGeneralChanges(
        window: [ArchGeneralChangeRow],
        allGeneral: [ArchGeneralChangeRow],
        changeUuid: String?,
        wantEveryCode: Bool
    ) -> (changes: [ArchGeneralChangeRow], stubs: [ArchGeneralChangeStub]?) {
        let generalChanges: [ArchGeneralChangeRow]
        let generalChangeStubs: [ArchGeneralChangeStub]?
        if wantEveryCode {
            generalChanges = window
            generalChangeStubs = nil
        } else {
            generalChanges = changeUuid.map { uuid in allGeneral.filter { $0.uuid == uuid } } ?? []
            generalChangeStubs = window.map { change in
                let code = CdeExcerpt.take(change.changeCode)
                return ArchGeneralChangeStub(
                    uuid: change.uuid,
                    seq: change.seq,
                    filePath: change.filePath,
                    className: change.className,
                    reasonBrief: change.reasonBrief,
                    changeDepth: change.changeDepth,
                    changeCodeExcerpt: code.excerpt,
                    changeCodeChars: code.chars,
                    changeCodeTruncated: code.truncated,
                    implementation: change.implementation
                )
            }
        }
        return (generalChanges, generalChangeStubs)
    }

    // MARK: - Option guard (m0025)

    /// Guards expansion until an undecided option set is resolved.
    ///
    /// Once any option row exists for a summary, change-row expansion is
    /// forbidden until exactly one option is selected. This is the
    /// pen-inversion gate, enforced as a Swift store guard by the m0016
    /// cross-table rule. Zero options allows legal direct expansion, so
    /// bot and rpi flows remain untouched by construction.
    ///
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - verb: The operation name, for error messaging.
    /// - Throws: `StoreError.invalidEntityTransition` when options exist but none is selected.
    private func requireDecisionBeforeExpansion(summaryUuid: String, verb: String) throws {
        guard
            let counts = try ArchitectureCounts.request(summaryUuid: summaryUuid).fetchOne(db),
            counts.optionCount > 0
        else { return }
        guard counts.selectedCount == 1 else {
            throw StoreError.invalidEntityTransition(
                entity: "architecture",
                from: "options_undecided",
                to: verb,
                reason:
                    "\(counts.optionCount) option(s) exist with none selected — run arch_decide first; only the selected option expands into change rows"
            )
        }
    }

    /// Fetches the parent summary uuid of a persistence change.
    ///
    /// - Parameter persistenceChangeUuid: The persistence change uuid.
    /// - Returns: The architecture summary uuid that owns the change.
    /// - Throws: `StoreError.notFound` when the change does not exist.
    private func parentSummaryUuid(persistenceChangeUuid: String) throws -> String {
        guard
            let uuid =
                try ArchitecturePersistenceChangeRecord
                .all()
                .withUuid(persistenceChangeUuid)
                .select(
                    ArchitecturePersistenceChangeRecord.Columns.architectureSummaryUuid,
                    as: String.self
                )
                .fetchOne(db)
        else {
            throw StoreError.notFound(
                entity: "architecture_persistence_change",
                key: persistenceChangeUuid
            )
        }
        return uuid
    }

    /// Returns a validated change kind or a default.
    ///
    /// - Parameters:
    ///   - raw: The raw change kind string, or nil to use the default.
    ///   - defaulting: The fallback kind; one of add, modify, rename, delete.
    /// - Returns: The validated kind, or the default if raw is nil or empty.
    /// - Throws: `StoreError.badRequest` when raw is not a recognized kind.
    private func validatedChangeKind(_ raw: String?, defaulting: String) throws -> String {
        guard let raw, !raw.isEmpty else { return defaulting }
        let legal = ["add", "modify", "rename", "delete"]
        guard legal.contains(raw) else {
            throw StoreError.badRequest(
                detail: "change_kind must be one of \(legal.joined(separator: "|")) (got '\(raw)')"
            )
        }
        return raw
    }

    /// Fetches architecture options matching a predicate.
    ///
    /// - Parameter predicate: A GRDB SQL expression to filter options.
    /// - Returns: The matching option rows, ordered by agent name.
    /// - Throws: Database errors.
    func fetchOptions(matching predicate: SQLExpression) throws -> [ArchitectureOptionRow] {
        try ArchitectureOptionRecord
            .all()
            .filter(predicate)
            .order(ArchitectureOptionRecord.Columns.agentName)
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches one architecture option by uuid.
    ///
    /// - Parameter uuid: The option uuid.
    /// - Returns: The option row, or nil if not found.
    /// - Throws: Database errors.
    private func fetchOption(uuid: String) throws -> ArchitectureOptionRow? {
        try fetchOptions(matching: ArchitectureOptionRecord.Columns.uuid == uuid).first
    }

    /// Fetches all architecture options for a summary.
    ///
    /// - Parameter summaryUuid: The architecture summary uuid.
    /// - Returns: The option rows for the summary.
    /// - Throws: Database errors.
    private func fetchOptions(summaryUuid: String) throws -> [ArchitectureOptionRow] {
        try fetchOptions(
            matching: ArchitectureOptionRecord.Columns.architectureSummaryUuid == summaryUuid
        )
    }

    /// Fetches the version of an architecture summary.
    ///
    /// - Parameter uuid: The summary uuid.
    /// - Returns: The summary's current version.
    /// - Throws: `StoreError.notFound` when the summary does not exist.
    private func summaryVersion(uuid: String) throws -> Int64 {
        guard
            let version =
                try ArchitectureSummaryRecord
                .all()
                .withUuid(uuid)
                .select(ArchitectureSummaryRecord.Columns.version, as: Int64.self)
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "architecture_summary", key: uuid)
        }
        return version
    }

    // MARK: - Comparison support

    /// Fetches every file path touched by changes, with counts and timestamps.
    ///
    /// One aggregate query (never per-row) that mirrors changeSummary: returns
    /// every distinct path this prompt's file changes touched, with change
    /// count and first and last modification timestamps. The result is keyed
    /// by path for the decoration lookup.
    ///
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: A map of file paths to their change counts and timestamps.
    /// - Throws: Database errors.
    private func touchedPaths(
        promptUuid: String
    ) throws -> [String: UnplannedChangeRow] {
        var byPath: [String: UnplannedChangeRow] = [:]
        for summary in try TouchedPathSummary.request(promptUuid: promptUuid).fetchAll(db) {
            byPath[summary.path] = summary.dto()
        }
        return byPath
    }

    /// Returns the implementation state for a file path.
    ///
    /// - Parameters:
    ///   - path: The file path to look up.
    ///   - touched: The map of touched paths and their change counts.
    /// - Returns: The implementation state with change count and timestamps, or zeros if untouched.
    private func implementationState(
        for path: String,
        touched: [String: UnplannedChangeRow]
    ) -> ChangeImplementationState {
        guard let entry = touched[path] else {
            return ChangeImplementationState(fileChangeCount: 0, firstChangedAt: nil, lastChangedAt: nil)
        }
        return ChangeImplementationState(
            fileChangeCount: entry.changeCount,
            firstChangedAt: entry.firstChangedAt,
            lastChangedAt: entry.lastChangedAt
        )
    }

    /// Fetches the filesystem root path for an instance via a prompt.
    ///
    /// The arch change-add paths normalize against the instance root reached
    /// via prompt → session → instance (the add payloads carry no context
    /// blocks). Returns empty when the chain is broken; the normalizer then
    /// applies only its lexical rules.
    ///
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The instance's absolute filesystem path, or empty if not found.
    /// - Throws: Database errors.
    func instanceRoot(promptUuid: String) throws -> String {
        let instance = TableAlias<InstanceRecord>()
        return
            try PromptRecord
            .all()
            .withUuid(promptUuid)
            .joining(
                required: PromptRecord.session
                    .joining(required: SessionRecord.instance.aliased(instance))
            )
            .select(instance[InstanceRecord.Columns.absoluteFileSystemPath], as: String.self)
            .fetchOne(db) ?? ""
    }

    // MARK: - Transition + fetch helpers

    /// Fetches a summary and asserts it has the required status.
    ///
    /// - Parameters:
    ///   - uuid: The summary uuid.
    ///   - required: The expected status; the function throws if it differs.
    ///   - verb: The operation name, for error messaging.
    /// - Returns: The summary row.
    /// - Throws: `StoreError.notFound` when not found, or `invalidEntityTransition` if status mismatches.
    private func requireSummary(
        uuid: String,
        at required: ArchitectureStatus,
        verb: String
    ) throws -> ArchitectureSummaryRow {
        guard let summary = try fetchSummary(uuid: uuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: uuid)
        }
        guard summary.architectureStatus == required else {
            throw StoreError.invalidEntityTransition(
                entity: "architecture",
                from: summary.status,
                to: verb,
                reason: "\(verb) is legal only while \(required.rawValue)"
            )
        }
        return summary
    }

    /// Transitions an architecture summary to a new status.
    ///
    /// - Parameters:
    ///   - summaryUuid: The summary uuid.
    ///   - expectedVersion: The expected current version.
    ///   - to: The target status.
    ///   - action: The action name, for event logging.
    ///   - requireFrom: The required current status before transition.
    /// - Returns: The updated summary.
    /// - Throws: `StoreError` variants for invalid state or version conflicts.
    func transition(
        summaryUuid: String,
        expectedVersion: Int64,
        to: ArchitectureStatus,
        action: String,
        requireFrom: ArchitectureStatus
    ) throws -> ArchSummaryResponse {
        guard let summary = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: summaryUuid)
        }
        guard let from = summary.architectureStatus else {
            throw StoreError.corruptState(entity: "architecture_summary", detail: "status '\(summary.status)'")
        }
        guard from == requireFrom, from.allowedNext.contains(to) else {
            throw StoreError.invalidEntityTransition(
                entity: "architecture",
                from: from.rawValue,
                to: to.rawValue,
                reason: "\(action) runs from \(requireFrom.rawValue) — this summary is \(from.rawValue)"
            )
        }
        // The pen-inversion gate applies at the SEAL too: proposing with
        // options still undecided would let the whole ceremony be skipped
        // (summarize/propose/approve never touch change rows).
        if action == "propose" {
            try requireDecisionBeforeExpansion(summaryUuid: summaryUuid, verb: "propose")
        }
        try core.updateBase(
            db,
            table: "architecture_summary",
            uuid: summaryUuid,
            expectedVersion: expectedVersion,
            set: ["status": to.rawValue]
        )
        try core.appendEvent(
            db,
            kind: .architectureChange,
            subjectUuid: summaryUuid,
            payload: Store.jsonPayload([
                "action": action, "from": from.rawValue, "to": to.rawValue,
                "prompt_uuid": summary.promptUuid,
            ])
        )
        try clarification.touchSessionForPrompt(promptUuid: summary.promptUuid)
        guard let updated = try fetchSummary(uuid: summaryUuid) else {
            throw StoreError.notFound(entity: "architecture_summary", key: summaryUuid)
        }
        return ArchSummaryResponse(summary: updated)
    }

    /// Fetches an architecture summary by uuid.
    ///
    /// - Parameter uuid: The summary uuid.
    /// - Returns: The summary row, or nil if not found.
    /// - Throws: Database errors.
    func fetchSummary(uuid: String) throws -> ArchitectureSummaryRow? {
        try fetchSummary(matching: ArchitectureSummaryRecord.Columns.uuid == uuid)
    }

    /// Fetches the architecture summary for a prompt.
    ///
    /// - Parameter promptUuid: The prompt uuid.
    /// - Returns: The summary row, or nil if no summary exists for the prompt.
    /// - Throws: Database errors.
    func fetchSummary(byPrompt promptUuid: String) throws -> ArchitectureSummaryRow? {
        try fetchSummary(matching: ArchitectureSummaryRecord.Columns.promptUuid == promptUuid)
    }

    /// Fetches an architecture summary matching a predicate.
    ///
    /// - Parameter predicate: A GRDB SQL expression to filter summaries.
    /// - Returns: The newest matching summary, or nil if none found.
    /// - Throws: Database errors.
    private func fetchSummary(matching predicate: SQLExpression) throws -> ArchitectureSummaryRow? {
        try ArchitectureSummaryRecord.all().newestFirst().filter(predicate).fetchOne(db)?.dto()
    }

    /// Maps a root's two change lists to wire rows carrying their implementation state.
    ///
    /// - Parameters:
    ///   - root: The architecture with its prefetched changes.
    ///   - touched: The prompt's touched paths, which decide implementation state.
    /// - Returns: The persistence changes and the general changes, each in `seq` order.
    private func plannedChanges(
        of root: ArchitectureWithChanges,
        touched: [String: UnplannedChangeRow]
    ) -> (persistence: [ArchPersistenceChangeRow], general: [ArchGeneralChangeRow]) {
        let persistence = root.persistenceChanges.map {
            $0.dto(implementation: implementationState(for: $0.change.filePath, touched: touched))
        }
        let general = root.generalChanges.map {
            $0.dto(implementation: implementationState(for: $0.filePath, touched: touched))
        }
        return (persistence, general)
    }

    /// Fetches persistence changes with their fields and implementation state.
    ///
    /// Two statements whatever the change count: the changes and their fields
    /// are fetched and composed together.
    ///
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - touched: The map of touched file paths and their change counts.
    /// - Returns: The persistence change rows with nested field changes and implementation state.
    /// - Throws: Database errors.
    private func fetchPersistenceChanges(
        summaryUuid: String,
        touched: [String: UnplannedChangeRow]
    ) throws -> [ArchPersistenceChangeRow] {
        try ArchPersistenceChangeWithFields.request()
            .filter(
                ArchitecturePersistenceChangeRecord.Columns.architectureSummaryUuid == summaryUuid
            )
            .fetchAll(db)
            .map {
                $0.dto(
                    implementation: implementationState(for: $0.change.filePath, touched: touched)
                )
            }
    }

    /// Fetches field changes for a persistence change.
    ///
    /// - Parameter changeUuid: The persistence change uuid.
    /// - Returns: The field change rows, ordered by sequence.
    /// - Throws: Database errors.
    private func fetchFieldChanges(
        changeUuid: String
    ) throws -> [ArchPersistenceFieldChangeRow] {
        try ArchitecturePersistenceFieldChangeRecord
            .all()
            .filter(
                ArchitecturePersistenceFieldChangeRecord.Columns.persistenceChangeUuid == changeUuid
            )
            .orderedBySeq()
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches general changes with their implementation state.
    ///
    /// - Parameters:
    ///   - summaryUuid: The architecture summary uuid.
    ///   - touched: The map of touched file paths and their change counts.
    /// - Returns: The general change rows, ordered by sequence, with implementation state.
    /// - Throws: Database errors.
    private func fetchGeneralChanges(
        summaryUuid: String,
        touched: [String: UnplannedChangeRow]
    ) throws -> [ArchGeneralChangeRow] {
        try ArchitectureGeneralChangeRecord
            .all()
            .filter(ArchitectureGeneralChangeRecord.Columns.architectureSummaryUuid == summaryUuid)
            .orderedBySeq()
            .fetchAll(db)
            .map { $0.dto(implementation: implementationState(for: $0.filePath, touched: touched)) }
    }
}
