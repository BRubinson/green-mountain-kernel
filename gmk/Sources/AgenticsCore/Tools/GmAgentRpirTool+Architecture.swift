// The architecture phase as one tool: options, the decision, and the change rows expanded from it.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeRpirArchitectureArguments: Sendable {

    @Guide(
        description: "Which architecture step to take.",
        .anyOf(GmAgentCdeRpirArchitectureTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(description: promptUuidGuide("this architecture belongs to"))
    var prompt_uuid: String?

    @Guide(description: summaryUuidGuide(to: "write to", "architecture"))
    var summary_uuid: String?

    @Guide(description: GM_TOOL_GUIDE_VERSION_CONFLICT)
    var expected_version: Int?

    @Guide(description: "Your methodology name. One plan per methodology.")
    var agent_name: String?

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID)
    var agent_id: String?

    @Guide(description: "The prose body: your whole proposal on open_option, the plan narrative on summarize.")
    var body: String?

    @Guide(
        description: """
            Option this proposal REPLACES, by uuid. Leave it out for a new \
            proposal. The old row stays as rejected history, and if it was the \
            selected plan the new one takes the selection. Needs expected_version.
            """
    )
    var supersedes_option_uuid: String?

    @Guide(description: "Name of the class, type or table being changed.")
    var class_name: String?

    @Guide(description: "Repo-relative file this change owns.")
    var file_path: String?

    @Guide(description: "Why this change, in one or two sentences, and what it costs.")
    var reason_brief: String?

    @Guide(description: "What is happening to it.", .anyOf(GM_TOOL_ANYOF_ARCH_CHANGE_KIND))
    var change_kind: String?

    @Guide(description: "For the entity. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dope_ref: String?

    @Guide(description: "The database change row these fields belong to, by uuid.")
    var persistence_change_uuid: String?

    @Guide(description: "Name of the field.")
    var field_name: String?

    @Guide(description: "Type of the field.")
    var data_type: String?

    @Guide(description: "Why this field is changing.")
    var change_reason: String?

    @Guide(description: "What the change is for.")
    var change_purpose: String?

    @Guide(description: "True if the field may be null.")
    var nullable: Bool?

    @Guide(description: "True if the field points at another table.")
    var is_foreign_key: Bool?

    @Guide(description: "What the field points at, only when is_foreign_key.")
    var fk_target: String?

    @Guide(description: "True if the field is indexed.")
    var is_indexed: Bool?

    @Guide(description: "Old field name, only when change_kind is rename.")
    var renamed_from: String?

    @Guide(description: "For the property. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dope_property_ref: String?

    @Guide(description: "How worked-out this code change is.", .anyOf(GM_TOOL_ANYOF_CHANGE_DEPTH))
    var change_depth: String?

    @Guide(
        description: """
            The instruction whoever implements this will follow. Write it to them, \
            not about them.
            """
    )
    var change_code: String?

    @Guide(description: "Which plan, by option uuid: the one to select on decide, one body to read on get.")
    var option_uuid: String?

    @Guide(description: "Read one change in full, by uuid. Leave it out for short versions of all.")
    var change_uuid: String?

    @Guide(
        description: """
            Why this plan won, and what the rejected ones still contribute. A \
            decision with no reasoning gets argued again later.
            """
    )
    var rationale: String?

    @Guide(description: "Cap the general change stub roster to its first N rows.")
    var limit: Int?

    @Guide(description: "page.next_cursor from the previous call. Leave it out for the first page.")
    var cursor: String?

    @Guide(description: "Page budget in bytes (default 30000, max 45000).")
    var page_bytes: Int?

    init(
        op: String,
        prompt_uuid: String? = nil,
        summary_uuid: String? = nil,
        expected_version: Int? = nil,
        agent_name: String? = nil,
        agent_id: String? = nil,
        body: String? = nil,
        supersedes_option_uuid: String? = nil,
        class_name: String? = nil,
        file_path: String? = nil,
        reason_brief: String? = nil,
        change_kind: String? = nil,
        dope_ref: String? = nil,
        persistence_change_uuid: String? = nil,
        field_name: String? = nil,
        data_type: String? = nil,
        change_reason: String? = nil,
        change_purpose: String? = nil,
        nullable: Bool? = nil,
        is_foreign_key: Bool? = nil,
        fk_target: String? = nil,
        is_indexed: Bool? = nil,
        renamed_from: String? = nil,
        dope_property_ref: String? = nil,
        change_depth: String? = nil,
        change_code: String? = nil,
        option_uuid: String? = nil,
        change_uuid: String? = nil,
        rationale: String? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        page_bytes: Int? = nil
    ) {
        self.op = op
        self.prompt_uuid = prompt_uuid
        self.summary_uuid = summary_uuid
        self.expected_version = expected_version
        self.agent_name = agent_name
        self.agent_id = agent_id
        self.body = body
        self.supersedes_option_uuid = supersedes_option_uuid
        self.class_name = class_name
        self.file_path = file_path
        self.reason_brief = reason_brief
        self.change_kind = change_kind
        self.dope_ref = dope_ref
        self.persistence_change_uuid = persistence_change_uuid
        self.field_name = field_name
        self.data_type = data_type
        self.change_reason = change_reason
        self.change_purpose = change_purpose
        self.nullable = nullable
        self.is_foreign_key = is_foreign_key
        self.fk_target = fk_target
        self.is_indexed = is_indexed
        self.renamed_from = renamed_from
        self.dope_property_ref = dope_property_ref
        self.change_depth = change_depth
        self.change_code = change_code
        self.option_uuid = option_uuid
        self.change_uuid = change_uuid
        self.rationale = rationale
        self.limit = limit
        self.cursor = cursor
        self.page_bytes = page_bytes
    }
}

// swiftlint:enable identifier_name

struct GmAgentCdeRpirArchitectureTool: GmAgentRpirTool {

    enum Op: String, CaseIterable, Sendable {
        case open
        case openOption = "open_option"
        case writePersistence = "write_persistence"
        case writeField = "write_field"
        case writeGeneral = "write_general"
        case summarize
        case propose
        case approve
        case revise
        case decide
        case get
    }

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.open,
            verbs: [.archOpen],
            requiredParams: ["prompt_uuid"],
            summary: """
                Open the prompt's architecture summary page — fetch-or-open, idempotent. \
                Opened explicitly like every summary; nothing opens it as a side effect.
                """
        ),
        GmAgentToolOp(
            Op.openOption,
            verbs: [.archOptionAdd],
            requiredParams: ["summary_uuid", "agent_name", "body"],
            summary: """
                Write YOUR methodology's option row (one per agent_name). To REVISE a \
                proposal, pass supersedes_option_uuid + expected_version together.
                """
        ),
        GmAgentToolOp(
            Op.writePersistence,
            verbs: [.archPersistAdd],
            requiredParams: ["summary_uuid", "class_name", "file_path", "reason_brief"],
            summary: """
                Record ONE persistence-tier change. Persistence rows come before general \
                rows because a schema or wire delta is what the plan gate is signed off against.
                """
        ),
        GmAgentToolOp(
            Op.writeField,
            verbs: [.archFieldAdd],
            requiredParams: [
                "persistence_change_uuid", "field_name", "data_type", "change_reason", "change_purpose",
                "nullable",
            ],
            summary: "Record ONE field-level change under a persistence change row."
        ),
        GmAgentToolOp(
            Op.writeGeneral,
            verbs: [.archGeneralAdd],
            requiredParams: ["summary_uuid", "file_path", "reason_brief", "change_depth", "change_code"],
            summary: """
                Record ONE general (non-persistence) change. change_depth is pseudo|draft|actual \
                — draft is a planned change not yet written.
                """
        ),
        GmAgentToolOp(
            Op.summarize,
            verbs: [.archSummarize],
            requiredParams: ["summary_uuid", "expected_version", "body"],
            summary: "Write the architecture summary's own body — the plan narrative over the expanded rows."
        ),
        GmAgentToolOp(
            Op.propose,
            verbs: [.archPropose],
            requiredParams: ["summary_uuid", "expected_version"],
            summary: "drafting → proposed: put the expanded plan on the table for the plan gate."
        ),
        GmAgentToolOp(
            Op.approve,
            verbs: [.archApprove],
            requiredParams: ["summary_uuid", "expected_version"],
            summary: """
                proposed → approved (terminal; unlocks implementation). The user's sign-off at \
                the plan gate is what authorizes this call.
                """
        ),
        GmAgentToolOp(
            Op.revise,
            verbs: [.archRevise],
            requiredParams: ["summary_uuid", "expected_version"],
            summary: """
                proposed → drafting: the revision edge. Reopens the summary so options and rows \
                can change; compose with open_option's supersede form to replace a proposal.
                """
        ),
        GmAgentToolOp(
            Op.decide,
            verbs: [.archDecide],
            // The decision's response carries every option BODY, so it can be over
            // budget while the write has already landed. There is nothing to narrow
            // on a write, so it names the read that shows the outcome instead.
            narrowing: CdeNarrowing(
                parameters: [],
                retryWith: "cde_rpir_architecture op=get (the decision and its rationale are on the summary; "
                    + "pass option_uuid for one option's body)"
            ),
            requiredParams: ["option_uuid", "expected_version", "rationale"],
            summary: """
                Select ONE option. Stamps it selected, rejects every sibling, and records why in \
                one atomic write. Only the selected option may expand into change rows. Primary only.
                """
        ),
        GmAgentToolOp(
            Op.get,
            verbs: [.archGet],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "option_uuid", "change_uuid"],
                retryWith: "cde_rpir_architecture op=get with cursor = page.next_cursor"
                    + "; option_uuid / change_uuid for one body"
            ),
            requiredParams: ["prompt_uuid"],
            summary: """
                The approved architecture with its implementation state: persistence changes \
                (whole) before general change stubs, each joined to its recorded file changes. \
                Long text arrives as windows; loop on cursor until page.next_cursor is null.
                """
        ),
    ]

    typealias Arguments = GmAgentCdeRpirArchitectureArguments
    typealias Output = String

    let name = "cde_rpir_architecture"
    let description = """
        The architecture phase: open the plan page, write one option per methodology, expand the \
        persistence, field and general change rows, write the narrative, run the plan gate \
        (propose → approve or revise), record the decision, and read the plan back.
        """

    init() {}
}
