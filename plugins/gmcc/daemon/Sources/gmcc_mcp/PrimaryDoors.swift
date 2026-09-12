import Foundation
import GMCCDaemonKit

/// The four tools that ADVANCE the workflow: move a prompt, decide among
/// architecture options, apply the calibrated review rank, seal the care
/// package.
///
/// THEY ARE ORDINARY PEN TOOLS. Nothing here refuses anyone — the four are
/// served by the same client as every other tool. What reserves them for the
/// primary is METHODOLOGY, not policy: cross-agent calibration and the choice
/// among options belong to one reader, and that is stated in the pen sheet and
/// in each agent's own definition. A persona that finds one of these in its
/// tool list may use it; a persona that does not, reports it is ready for one.
func makePrimaryDoorTools() -> [Tool] { [

    Tool(
        name: "prompt_set_status",
        description: """
            THE ONLY DOOR THAT MOVES A PROMPT. draft → clarifying → architecting → \
            implementing → reviewing → done. Creates the phase's backing summary as a side \
            effect, and claims (or on `done`, releases) the prompt's activation for this \
            instance. Primary only.
            """,
        params: [
            ("prompt_uuid", "string", "The prompt to move", true),
            ("expected_version", "number", "The prompt version this write is based on", true),
            ("status", "string", "clarifying | architecting | implementing | reviewing | done", true),
        ],
        run: { args, client in
            let raw = try args.string("status")
            guard let status = PromptStatus(rawValue: raw) else {
                throw ToolError(message: "unknown status '\(raw)' — expected one of: \(PromptStatus.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return try client.setPromptStatus(PromptSetStatusRequest(
                promptUuid: try args.string("prompt_uuid"),
                expectedVersion: try args.int64("expected_version"),
                status: status,
                clientKey: ClientKey.resolve()))
        }),

    Tool(
        name: "arch_decide",
        description: """
            Select ONE architecture option. Stamps it selected, rejects every sibling, and \
            records why in one atomic write — the rationale is not optional, because a decision \
            whose reasoning is not written down is re-litigated. Only the selected option may \
            expand into change rows. Primary only.
            """,
        params: [
            ("option_uuid", "string", "The option to select", true),
            ("expected_version", "number", "That option's version", true),
            ("rationale", "string", "Why this option won, and what the rejected siblings contribute", true),
        ],
        // ArchDecideResponse carries every option BODY — four architect essays
        // in a team flow, 124,583 characters on the prompt that added this
        // guard — so the response is over budget while the decision itself is
        // already committed. There is nothing to narrow on the WRITE and no
        // degrade is possible, because the only way to re-run it is to decide
        // again. So it names the read that shows the outcome instead; the
        // write-aware guard turns this into "completed, read it back".
        narrowing: PenNarrowing(
            parameters: [],
            retryWith: "arch_get (the decision and its rationale are on the summary; "
                + "pass option_uuid for one option's body)"),
        run: { args, client in
            try client.archDecide(ArchDecideRequest(
                optionUuid: try args.string("option_uuid"),
                expectedVersion: try args.int64("expected_version"),
                rationale: try args.string("rationale")))
        }),

    Tool(
        name: "review_rank",
        description: """
            Apply the calibrated review rating batch. Version-less and atomic: ranking is \
            CROSS-AGENT calibration and belongs to one reader, which is why an agent rates only \
            its own findings and never calls this. 0 = critical, 999 = ignore, read threshold \
            100. Primary only.
            """,
        params: [
            ("summary_uuid", "string", "The review summary being ranked", true),
            ("ratings", "array<object>", "Entries shaped {finding_uuid, rating} — as JSON objects, one per finding", true),
        ],
        run: { args, client in
            guard case let .array(items)? = args.json["ratings"] else {
                throw ToolError(message: "ratings must be an array of {finding_uuid, rating}")
            }
            let ratings: [FindingRating] = try items.map { item in
                guard let uuid = item["finding_uuid"]?.stringValue,
                      let rating = item["rating"]?.intValue
                else { throw ToolError(message: "each rating needs finding_uuid and rating") }
                guard (0...999).contains(rating) else {
                    throw ToolError(message: "rating must be 0-999 (0 = critical, 999 = ignore), got \(rating)")
                }
                return FindingRating(findingUuid: uuid, rating: rating)
            }
            return try client.reviewRank(ReviewRankRequest(
                summaryUuid: try args.string("summary_uuid"),
                ratings: ratings))
        }),

    Tool(
        name: "care_package_complete",
        description: """
            Seal the care package with the clarified intent — building → ready. THE INTENT \
            BLOB LIVES ONLY HERE: it is what every downstream agent reads instead of re-deriving \
            the decision from raw exploration. Primary only.
            """,
        params: [
            ("package_uuid", "string", "The care package to seal", true),
            ("expected_version", "number", "The package version this write is based on", true),
            ("clarified_intent", "string", "The decided intent, in full — what was chosen, and what was ruled out and why", true),
        ],
        run: { args, client in
            try client.carePackageComplete(CarePackageCompleteRequest(
                packageUuid: try args.string("package_uuid"),
                expectedVersion: try args.int64("expected_version"),
                clarifiedIntent: try args.string("clarified_intent")))
        }),
]}
