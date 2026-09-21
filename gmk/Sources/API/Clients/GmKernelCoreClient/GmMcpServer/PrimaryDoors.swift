import Foundation

/// The four ops that ADVANCE the workflow: move a prompt, decide among
/// architecture options, apply the calibrated review rank, seal the care
/// package.
///
/// THEY REFUSE NO ONE. What reserves them for the primary is METHODOLOGY, not
/// policy: cross-agent calibration and the choice among options belong to one
/// reader. A persona holding the tool may call the op; a persona without it
/// reports that it is ready for one.

/// This file's contribution to `CdeDispatch`.
nonisolated(unsafe) let primaryDoorArms: CdeArms = [
    "cde_prompt": ["set_status": setStatusArm()],
    "cde_rpir_architecture": ["decide": archDecideArm()],
    "cde_rpir_review": ["rank": reviewRankArm()],
    "cde_rpir_clarify": ["package_close": carePackageCloseArm()],
]

private func setStatusArm() -> CdeArm {
    { args, client in
        let raw = try args.string("status")
        guard let status = PromptStatus(rawValue: raw) else {
            throw ToolError(
                message:
                    "unknown status '\(raw)' — expected one of: \(PromptStatus.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return try client.setPromptStatus(
            PromptSetStatusRequest(
                promptUuid: try args.string("prompt_uuid"),
                expectedVersion: try args.int64("expected_version"),
                status: status,
                clientKey: ClientKey.resolve()
            )
        )
    }
}

private func archDecideArm() -> CdeArm {
    { args, client in
        try client.archDecide(
            ArchDecideRequest(
                optionUuid: try args.string("option_uuid"),
                expectedVersion: try args.int64("expected_version"),
                rationale: try args.string("rationale")
            )
        )
    }
}

/// The calibrated batch arrives as `"<finding-uuid>:<0-999>"` strings, the one
/// shape the roster declares and the same one `cde_rpir_explore` op rank takes.
private func reviewRankArm() -> CdeArm {
    { args, client in
        let raw = args.optStrings("ratings") ?? []
        guard !raw.isEmpty else {
            throw ToolError(message: "pass at least one rating as \"<finding-uuid>:<0-999>\"")
        }
        let ratings: [FindingRating] = try raw.map { pair in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let rating = Int(parts[1]), (0...999).contains(rating) else {
                throw ToolError(message: "rating '\(pair)' is not <finding-uuid>:<0-999>")
            }
            return FindingRating(findingUuid: String(parts[0]), rating: rating)
        }
        return try client.reviewRank(
            ReviewRankRequest(
                summaryUuid: try args.string("summary_uuid"),
                ratings: ratings
            )
        )
    }
}

private func carePackageCloseArm() -> CdeArm {
    { args, client in
        try client.carePackageComplete(
            CarePackageCompleteRequest(
                packageUuid: try args.string("package_uuid"),
                expectedVersion: try args.int64("expected_version"),
                clarifiedIntent: try args.string("clarified_intent")
            )
        )
    }
}
