import Foundation

/// The phase ops, each a door for a daemon verb an agent would otherwise have
/// to reach through the shell, keeping the pen's promise that where a pen tool
/// exists it is the write path. A MISSING DOOR IS ONLY VISIBLE TO A
/// BIDIRECTIONAL GATE: asking only "does every served tool have a VerbSpec?"
/// passes a pen serving nothing. See `GmCdeTools.rosterProblems()`.

/// This file's contribution to `CdeDispatch` — the writes of the clarification,
/// briefing-close, architecture, review and kbite phases.
///
/// The op names are the
/// roster's; an op here the roster does not declare is reported at startup.
nonisolated(unsafe) let phaseDoorArms: CdeArms = [
    "cde_rpir_briefing": briefingPhaseArms(),
    "cde_rpir_clarify": clarifyPhaseArms(),
    "cde_rpir_architecture": architecturePhaseArms(),
    "cde_rpir_review": reviewPhaseArms(),
    "cde_kbite": kbitePhaseArms(),
]

/// Returns the arms for briefing phase operations.
///
/// - Returns: A mapping of op names to their handlers.
private func briefingPhaseArms() -> [String: CdeArm] {
    var briefing: [String: CdeArm] = [:]
    briefing["close"] = { args, client in
        try client.briefingComplete(
            BriefingCompleteRequest(
                briefingUuid: try args.string("briefing_uuid"),
                expectedVersion: try args.int64("expected_version"),
                dopeRefs: args.optStrings("dope_refs") ?? [],
                kbiteRefs: args.optStrings("kbite_refs") ?? [],
                fileChangeRefs: args.optStrings("file_change_refs") ?? [],
                agentId: args.optString("agent_id")
            )
        )
    }
    return briefing
}

/// Returns the arms for clarification phase operations.
///
/// - Returns: A mapping of op names to their handlers.
private func clarifyPhaseArms() -> [String: CdeArm] {
    var clarify: [String: CdeArm] = [:]
    clarify["open"] = { args, client in
        try client.clarifyOpen(
            ClarifyOpenRequest(
                promptUuid: try args.string("prompt_uuid")
            )
        )
    }
    clarify["answer"] = { args, client in
        try client.clarifyAnswer(
            ClarifyAnswerRequest(
                questionUuid: try args.string("question_uuid"),
                expectedVersion: try args.int64("expected_version"),
                answerText: args.optString("answer_text"),
                selectedOptionUuids: args.optStrings("selected_option_uuids"),
                skip: args.optBool("skip") ?? false
            )
        )
    }
    clarify["seal"] = { args, client in
        try client.clarifySeal(
            ClarifySealRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version")
            )
        )
    }
    clarify["finalize"] = { args, client in
        try client.clarifyFinalize(
            ClarifyFinalizeRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version")
            )
        )
    }
    // The selector is the CLARIFICATION SUMMARY uuid, not the prompt uuid: the
    // package hangs off the summary that produced it.
    clarify["package_open"] = { args, client in
        try client.carePackageOpen(
            CarePackageOpenRequest(
                summaryUuid: try args.string("summary_uuid")
            )
        )
    }
    return clarify
}

/// Returns the arms for architecture phase operations.
///
/// - Returns: A mapping of op names to their handlers.
private func architecturePhaseArms() -> [String: CdeArm] {
    architectureRowArms().merging(architectureStatusArms()) { _, latest in latest }
}

/// Returns the arms for architecture row operations.
///
/// Handles the summary page and its associated change records.
///
/// - Returns: A mapping of op names to their handlers.
private func architectureRowArms() -> [String: CdeArm] {
    var architecture: [String: CdeArm] = [:]
    architecture["open"] = { args, client in
        try client.archOpen(
            ArchOpenRequest(
                promptUuid: try args.string("prompt_uuid")
            )
        )
    }
    architecture["write_persistence"] = { args, client in
        try client.archPersistAdd(
            ArchPersistAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                className: try args.string("class_name"),
                filePath: try args.string("file_path"),
                reasonBrief: try args.string("reason_brief"),
                changeKind: args.optString("change_kind"),
                dopeRef: args.optString("dope_ref")
            )
        )
    }
    architecture["write_general"] = { args, client in
        let raw = try args.string("change_depth")
        guard let depth = ChangeDepth(rawValue: raw) else {
            throw ToolError(message: "change_depth must be pseudo, draft or actual — got '\(raw)'")
        }
        return try client.archGeneralAdd(
            ArchGeneralAddRequest(
                summaryUuid: try args.string("summary_uuid"),
                filePath: try args.string("file_path"),
                reasonBrief: try args.string("reason_brief"),
                changeDepth: depth,
                changeCode: try args.string("change_code"),
                className: args.optString("class_name")
            )
        )
    }
    architecture["write_field"] = { args, client in
        try client.archFieldAdd(
            ArchFieldAddRequest(
                persistenceChangeUuid: try args.string("persistence_change_uuid"),
                fieldName: try args.string("field_name"),
                dataType: try args.string("data_type"),
                changeReason: try args.string("change_reason"),
                changePurpose: try args.string("change_purpose"),
                nullable: try args.bool("nullable"),
                isForeignKey: args.optBool("is_foreign_key") ?? false,
                fkTarget: args.optString("fk_target"),
                isIndexed: args.optBool("is_indexed") ?? false,
                changeKind: args.optString("change_kind"),
                renamedFrom: args.optString("renamed_from"),
                dopePropertyRef: args.optString("dope_property_ref")
            )
        )
    }
    return architecture
}

/// Returns the arms for architecture status operations.
///
/// Handles the summary's body and status edges: drafting → proposed →
/// approved, and revision.
///
/// - Returns: A mapping of op names to their handlers.
private func architectureStatusArms() -> [String: CdeArm] {
    var architecture: [String: CdeArm] = [:]
    architecture["summarize"] = { args, client in
        try client.archSummarize(
            ArchSummarizeRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version"),
                body: try args.string("body")
            )
        )
    }
    architecture["propose"] = { args, client in
        try client.archPropose(
            ArchProposeRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version")
            )
        )
    }
    architecture["approve"] = { args, client in
        try client.archApprove(
            ArchApproveRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version")
            )
        )
    }
    architecture["revise"] = { args, client in
        try client.archRevise(
            ArchReviseRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version")
            )
        )
    }
    return architecture
}

/// Returns the arms for review phase operations.
///
/// - Returns: A mapping of op names to their handlers.
private func reviewPhaseArms() -> [String: CdeArm] {
    var review: [String: CdeArm] = [:]
    review["open"] = { args, client in
        try client.reviewOpen(
            ReviewOpenRequest(
                promptUuid: try args.string("prompt_uuid")
            )
        )
    }
    // `open` is not an accepted resolution: it is the initial state, so
    // resolving TO it would move backwards through an append-only record.
    review["resolve"] = { args, client in
        let raw = try args.string("status")
        guard let status = ReviewFindingStatus(rawValue: raw), status != .open else {
            throw ToolError(
                message: "status must be fixed, accepted or wont_fix — '\(raw)' is not a resolution"
            )
        }
        return try client.reviewResolve(
            ReviewResolveRequest(
                findingUuid: try args.string("finding_uuid"),
                expectedVersion: try args.int64("expected_version"),
                status: status
            )
        )
    }
    review["complete"] = { args, client in
        let raw = try args.string("verdict")
        guard let verdict = ReviewVerdict(rawValue: raw) else {
            throw ToolError(
                message: "verdict must be approved, approved_with_nits or changes_requested — got '\(raw)'"
            )
        }
        return try client.reviewComplete(
            ReviewCompleteRequest(
                summaryUuid: try args.string("summary_uuid"),
                expectedVersion: try args.int64("expected_version"),
                overview: try args.string("overview"),
                verdict: verdict
            )
        )
    }
    return review
}

/// Returns the arms for kbite phase operations.
///
/// - Returns: A mapping of op names to their handlers.
private func kbitePhaseArms() -> [String: CdeArm] {
    var kbite: [String: CdeArm] = [:]
    kbite["open_maw"] = { args, client in
        try client.openKbiteMaw(
            KbiteMawOpenRequest(
                kbiteName: try args.string("kbite_name"),
                mawPath: try args.string("maw_path")
            )
        )
    }
    kbite["digest"] = { args, client in
        try client.digestKbite(
            KbiteDigestRequest(
                code: try args.string("code"),
                kbiteOpenPath: try args.string("kbite_open_path")
            )
        )
    }
    return kbite
}
