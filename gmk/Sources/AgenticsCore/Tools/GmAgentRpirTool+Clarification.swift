// The clarification phase as one tool: questions, notes, answers and the care package.

import Foundation
import FoundationModels

// The generated property names ARE the wire argument names the served tool
// reads, so they are spelled snake_case here.
// swiftlint:disable identifier_name

@Generable
struct GmAgentCdeRpirClarifyArguments: Sendable {

    @Guide(
        description: """
            Which clarification move to make. Every other argument belongs to \
            one op; pass only that op's arguments.
            """,
        .anyOf(GmAgentCdeRpirClarifyTool.Op.allCases.map(\.rawValue))
    )
    var op: String

    @Guide(description: "Explicit prompt uuid (omit to resolve YOUR workflow's prompt). Ops open, get, package_get.")
    var prompt_uuid: String?

    @Guide(
        description: """
            The clarification summary uuid. Ops write_questions, write_notes, \
            seal, finalize, package_open.
            """
    )
    var summary_uuid: String?

    @Guide(description: GM_TOOL_GUIDE_VERSION_CONFLICT + " Ops answer, seal, finalize, package_close.")
    var expected_version: Int?

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME + " Ops write_questions, write_notes.")
    var agent_name: String?

    @Guide(description: GM_TOOL_GUIDE_AGENT_ID + " Ops write_questions, write_notes.")
    var agent_id: String?

    @Guide(
        description: """
            Op write_questions: the question, written so a human can answer it \
            without reading code.
            """
    )
    var question: String?

    @Guide(
        description: """
            Op write_questions: the answers to offer, in order. Write real \
            alternatives with their trade-offs, not yes/no.
            """
    )
    var options: [String]?

    @Guide(
        description: """
            Op write_notes: the note text. Op package_write: the curated \
            exploration body, written out again with more intent — copy and \
            sharpen what was already found, do not go exploring again.
            """
    )
    var body: String?

    @Guide(description: "Op write_notes: how important, 0 is critical and 999 is ignore.", .range(0...999))
    var weight: Int?

    @Guide(
        description: """
            Op answer: which question was answered. Op write_notes: attach the \
            note to an answered question.
            """
    )
    var question_uuid: String?

    @Guide(description: "Op write_notes: exploration_finding | briefing | question | other.")
    var confused_entity_type: String?

    @Guide(description: "Op write_notes: soft ref to the confusing entity, by uuid.")
    var confused_entity_uuid: String?

    @Guide(
        description: """
            Op answer: what the human said, in full — including WHY, since a \
            bare option pick loses the reasoning.
            """
    )
    var answer_text: String?

    @Guide(description: "Op answer: which offered options they picked, by uuid.")
    var selected_option_uuids: [String]?

    @Guide(
        description: """
            Op answer: true if the question was deliberately not asked — \
            malformed, superseded or moot. The record keeps it either way.
            """
    )
    var skip: Bool?

    @Guide(description: "Op get: return exactly this note in full and nothing else.")
    var note_uuid: String?

    @Guide(
        description: """
            Op get: only return notes this important or better, 0 to 999. Use a \
            small number to keep the answer short.
            """,
        .range(0...999)
    )
    var note_weight_max: Int?

    @Guide(
        description: """
            Ops get, package_get: page.next_cursor from the previous call \
            (opaque). Omit for the first page.
            """
    )
    var cursor: String?

    @Guide(description: "Ops get, package_get: page budget in bytes (default 30000, max 45000).")
    var page_bytes: Int?

    @Guide(description: "The care package uuid. Ops package_write, package_close.")
    var package_uuid: String?

    @Guide(
        description: "Op package_write: what sort of ref this is.",
        .anyOf(GM_TOOL_ANYOF_CARE_REF_KIND)
    )
    var kind: String?

    @Guide(description: "Op package_write, kind dope. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dope_code: String?

    @Guide(description: "Op package_write, kind dope: the curatorial note on the ref.")
    var note: String?

    @Guide(description: "Op package_write, kind kbite. " + GM_TOOL_GUIDE_KBITE_FILE_UUID)
    var kbite_file_uuid: String?

    @Guide(description: "Op package_write, kind exploration: a title for the copied finding.")
    var title: String?

    @Guide(description: "Op package_write, kind exploration: the repo-relative anchor.")
    var file_path: String?

    @Guide(description: "Op package_write, kind exploration: the finding this copy came from, by uuid.")
    var source_finding_uuid: String?

    @Guide(
        description: """
            Op package_close: what was decided, in full — what was chosen, and \
            what was ruled out and why. This is the only place it is written down.
            """
    )
    var clarified_intent: String?

    @Guide(description: "Op package_get: read exactly this exploration ref's curated body in full, the rest as stubs.")
    var ref_uuid: String?
}

// swiftlint:enable identifier_name

/// The clarification record and the care package hanging off it. The package is
/// selected by the CLARIFICATION SUMMARY uuid on `package_open` and by the
/// prompt on `package_get`, because it hangs off the summary that produced it.
struct GmAgentCdeRpirClarifyTool: GmAgentRpirTool {

    /// Raw values are the wire op names; the case names stay lowerCamelCase so
    /// the repo's identifier rule holds.
    enum Op: String, CaseIterable, Sendable {
        case open
        case writeQuestions = "write_questions"
        case writeNotes = "write_notes"
        case answer
        case seal
        case finalize
        case get
        case packageOpen = "package_open"
        case packageWrite = "package_write"
        case packageClose = "package_close"
        case packageGet = "package_get"
    }

    typealias Arguments = GmAgentCdeRpirClarifyArguments

    typealias Output = String

    static let ops: [GmAgentToolOp] = [
        GmAgentToolOp(
            Op.open,
            verbs: [.clarifyOpen],
            requiredParams: ["prompt_uuid"],
            summary: "Open the prompt's clarification summary. No status move — the prompt is already initiated."
        ),
        GmAgentToolOp(
            Op.writeQuestions,
            verbs: [.clarifyQuestionAdd],
            requiredParams: ["summary_uuid", "question"],
            summary: "Insert ONE user-facing question with its ordered options, while the summary is building."
        ),
        GmAgentToolOp(
            Op.writeNotes,
            verbs: [.clarifyNoteAdd],
            requiredParams: ["summary_uuid", "body"],
            summary: "Insert ONE internal note, weighted 0 (critical) to 999 (ignore), in any summary state."
        ),
        GmAgentToolOp(
            Op.answer,
            verbs: [.clarifyAnswer],
            requiredParams: ["question_uuid", "expected_version"],
            summary: "Record the user's answer to ONE question, or mark it skipped."
        ),
        GmAgentToolOp(
            Op.seal,
            verbs: [.clarifySeal],
            requiredParams: ["summary_uuid", "expected_version"],
            summary: "building → answering. Answers are writable only after this seal. The primary's call."
        ),
        GmAgentToolOp(
            Op.finalize,
            verbs: [.clarifyFinalize],
            requiredParams: ["summary_uuid", "expected_version"],
            summary: "answering → complete, once every question is answered or skipped. The LATER move, after seal."
        ),
        GmAgentToolOp(
            Op.get,
            verbs: [.clarifyGet],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "note_uuid"],
                retryWith: "cde_rpir_clarify op=get with cursor = page.next_cursor; note_uuid for one body"
            ),
            summary: "The summary, its questions with answers, and its notes. The package stays a stub."
        ),
        GmAgentToolOp(
            Op.packageOpen,
            verbs: [.carePackageOpen],
            requiredParams: ["summary_uuid"],
            summary: "Open the care package on a clarification summary — the selector is the SUMMARY uuid."
        ),
        GmAgentToolOp(
            Op.packageWrite,
            verbs: [.carePackageRefAdd],
            requiredParams: ["package_uuid", "kind"],
            summary: "Add ONE ref while building: a dope code, a kbite file, or a curated exploration COPY."
        ),
        GmAgentToolOp(
            Op.packageClose,
            verbs: [.carePackageComplete],
            requiredParams: ["package_uuid", "expected_version", "clarified_intent"],
            summary: "Seal the package with the clarified intent — building → ready. The primary's call."
        ),
        GmAgentToolOp(
            Op.packageGet,
            verbs: [.carePackageGet],
            narrowing: CdeNarrowing(
                parameters: ["cursor", "page_bytes", "ref_uuid"],
                retryWith: "cde_rpir_clarify op=package_get with cursor = page.next_cursor; ref_uuid for one body"
            ),
            summary: "The sealed package on its own: the intent, its refs, and the curated copies as a stub roster."
        ),
    ]

    let name = "cde_rpir_clarify"
    let description = """
        The clarification record: questions for the human, private notes, their \
        answers, and the care package that carries the decided intent forward.
        """

    init() {}
}
