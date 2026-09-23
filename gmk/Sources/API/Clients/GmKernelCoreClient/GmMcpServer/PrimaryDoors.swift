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

/// Returns the arm for cde_prompt set_status operation.
///
/// - Returns: The arm handler for setting prompt status.
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

/// Returns the arm for architecture decide operation.
///
/// - Returns: The arm handler for deciding among architecture options.
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

/// Returns the arm for review rank operation.
///
/// The calibrated batch arrives as "<finding-uuid>:<0-999>" strings,
/// the shape the roster declares and `cde_rpir_explore` op rank takes.
///
/// - Returns: The arm handler for ranking review findings.
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

/// Returns the arm for care package close operation.
///
/// - Returns: The arm handler for closing the care package.
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
