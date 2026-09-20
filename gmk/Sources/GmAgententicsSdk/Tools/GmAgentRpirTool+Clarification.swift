// Agent tools for the clarification phase: questions, notes, answers and the care package.

import Foundation
import FoundationModels

@Generable
struct GmAgentRpirOpenClarificationArguments: Sendable {
    @Guide(description: promptUuidGuide("to open questions for"))
    var promptUuid: String

    init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

struct GmAgentRpirOpenClarificationTool: GmAgentRpirTool {
    let name = "rpir_open_clarification"
    let description = "Start the question list."

    init() {}

    func call(arguments _: GmAgentRpirOpenClarificationArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_OPEN")
    }
}

@Generable
struct GmAgentClarificationQuestion: Sendable {
    @Guide(description: "The question, written so a human can answer it without reading code.")
    var question: String

    @Guide(
        description: """
            The answers to offer, in order. Write real alternatives with their \
            trade-offs, not yes/no.
            """
    )
    var options: [String]

    init(question: String, options: [String] = []) {
        self.question = question
        self.options = options
    }
}

@Generable
struct GmAgentRpirWriteClarificationQuestionsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "question list"))
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    var agentName: String

    @Guide(description: "All the questions to write in one go.")
    var questions: [GmAgentClarificationQuestion]

    init(
        summaryUuid: String,
        agentName: String,
        questions: [GmAgentClarificationQuestion]
    ) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.questions = questions
    }
}

struct GmAgentRpirWriteClarificationQuestionsTool: GmAgentRpirTool {
    let name = "rpir_write_clarification_questions"
    let description = "Write down many questions for the human."

    init() {}

    func call(
        arguments _: GmAgentRpirWriteClarificationQuestionsArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_QUESTION_ADD (looped)")
    }
}

@Generable
struct GmAgentClarificationNote: Sendable {
    @Guide(description: "The note.")
    var body: String

    @Guide(description: "How important: 0 is critical, 999 is ignore.", .range(0...999))
    var weight: Int

    init(body: String, weight: Int = 100) {
        self.body = body
        self.weight = weight
    }
}

@Generable
struct GmAgentRpirWriteClarificationNotesArguments: Sendable {
    @Guide(description: "Which question list the notes belong to, by uuid.")
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    var agentName: String

    @Guide(description: "All the notes to write in one go.")
    var notes: [GmAgentClarificationNote]

    init(summaryUuid: String, agentName: String, notes: [GmAgentClarificationNote]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.notes = notes
    }
}

struct GmAgentRpirWriteClarificationNotesTool: GmAgentRpirTool {
    let name = "rpir_write_clarification_notes"
    let description = "Write down many private notes."

    init() {}

    func call(
        arguments _: GmAgentRpirWriteClarificationNotesArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_NOTE_ADD (looped)")
    }
}

@Generable
struct GmAgentRpirAnswerClarificationQuestionArguments: Sendable {
    @Guide(description: "Which question was answered, by uuid.")
    var questionUuid: String

    @Guide(description: "Version of the question you read.")
    var expectedVersion: Int

    @Guide(description: "What the human said, in their words.")
    var answerText: String

    @Guide(description: "Which offered options they picked, by uuid.")
    var selectedOptionUuids: [String]

    @Guide(description: "True if they declined to answer.")
    var skip: Bool

    init(
        questionUuid: String,
        expectedVersion: Int,
        answerText: String,
        selectedOptionUuids: [String] = [],
        skip: Bool = false
    ) {
        self.questionUuid = questionUuid
        self.expectedVersion = expectedVersion
        self.answerText = answerText
        self.selectedOptionUuids = selectedOptionUuids
        self.skip = skip
    }
}

struct GmAgentRpirAnswerClarificationQuestionTool: GmAgentRpirTool {
    let name = "rpir_answer_clarification_question"
    let description = "Human said this."

    init() {}

    func call(
        arguments _: GmAgentRpirAnswerClarificationQuestionArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_ANSWER")
    }
}

@Generable
struct GmAgentRpirFinalizeClarificationArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "finish", "question list"))
    var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    var expectedVersion: Int

    init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

struct GmAgentRpirFinalizeClarificationTool: GmAgentRpirTool {
    let name = "rpir_finalize_clarification"
    let description = "Questions all done."

    init() {}

    func call(
        arguments _: GmAgentRpirFinalizeClarificationArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_FINALIZE")
    }
}

@Generable
struct GmAgentRpirSealClarificationArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "seal", "question list"))
    var summaryUuid: String

    @Guide(description: "Version of the summary you read.")
    var expectedVersion: Int

    init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

struct GmAgentRpirSealClarificationTool: GmAgentRpirTool {
    let name = "rpir_seal_clarification"
    let description = "Questions written; open them for answers."

    init() {}

    func call(
        arguments _: GmAgentRpirSealClarificationArguments
    ) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_SEAL")
    }
}

@Generable
struct GmAgentRpirOpenCarePackageArguments: Sendable {
    @Guide(description: "Which question list the box belongs to, by uuid.")
    var summaryUuid: String

    init(summaryUuid: String) {
        self.summaryUuid = summaryUuid
    }
}

struct GmAgentRpirOpenCarePackageTool: GmAgentRpirTool {
    let name = "rpir_open_care_package"
    let description = "Get an empty box ready for the next agent."

    init() {}

    func call(arguments _: GmAgentRpirOpenCarePackageArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_OPEN")
    }
}

@Generable
struct GmAgentCareRef: Sendable {
    @Guide(description: "What sort of thing this is.", .anyOf(GM_TOOL_ANYOF_CARE_REF_KIND))
    var kind: String

    @Guide(description: "For a dope ref. " + GM_TOOL_GUIDE_DOPE_CODE)
    var dopeCode: String

    @Guide(description: "For a kbite ref. " + GM_TOOL_GUIDE_KBITE_FILE_UUID)
    var kbiteFileUuid: String

    @Guide(description: "For an exploration ref: a title for the copied finding.")
    var title: String

    @Guide(
        description: """
            For an exploration ref: the finding written out again with more intent. \
            Copy and sharpen what was already found — do not go exploring again.
            """
    )
    var body: String

    init(
        kind: String,
        dopeCode: String = "",
        kbiteFileUuid: String = "",
        title: String = "",
        body: String = ""
    ) {
        self.kind = kind
        self.dopeCode = dopeCode
        self.kbiteFileUuid = kbiteFileUuid
        self.title = title
        self.body = body
    }
}

@Generable
struct GmAgentRpirWriteCarePackageArguments: Sendable {
    @Guide(description: "Which box to fill, by uuid.")
    var packageUuid: String

    @Guide(description: "Everything to put in the box, in one go.")
    var refs: [GmAgentCareRef]

    init(packageUuid: String, refs: [GmAgentCareRef]) {
        self.packageUuid = packageUuid
        self.refs = refs
    }
}

struct GmAgentRpirWriteCarePackageTool: GmAgentRpirTool {
    let name = "rpir_write_care_package"
    let description = "Put the good bits in the box for the next agent."

    init() {}

    func call(arguments _: GmAgentRpirWriteCarePackageArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_REF_ADD (looped)")
    }
}

@Generable
struct GmAgentRpirCloseCarePackageArguments: Sendable {
    @Guide(description: "Which box to seal, by uuid.")
    var packageUuid: String

    @Guide(description: "Version of the box you read.")
    var expectedVersion: Int

    @Guide(
        description: """
            What was decided, in full: what was chosen, and what was ruled out and \
            why. This is the only place it is written down.
            """
    )
    var clarifiedIntent: String

    init(packageUuid: String, expectedVersion: Int, clarifiedIntent: String) {
        self.packageUuid = packageUuid
        self.expectedVersion = expectedVersion
        self.clarifiedIntent = clarifiedIntent
    }
}

struct GmAgentRpirCloseCarePackageTool: GmAgentRpirTool {
    let name = "rpir_close_care_package"
    let description = "Box is ready."

    init() {}

    func call(arguments _: GmAgentRpirCloseCarePackageArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_COMPLETE")
    }
}

@Generable
struct GmAgentRpirGetClarificationArguments: Sendable {
    @Guide(description: promptUuidGuide("'s questions to read"))
    var promptUuid: String

    @Guide(
        description: """
            Only return notes this important or better, 0 to 999. Use a small \
            number to keep the answer short.
            """,
        .range(0...999)
    )
    var noteWeightMax: Int

    init(promptUuid: String, noteWeightMax: Int = 100) {
        self.promptUuid = promptUuid
        self.noteWeightMax = noteWeightMax
    }
}

struct GmAgentRpirGetClarificationTool: GmAgentRpirTool {
    let name = "rpir_get_clarification"
    let description = "Show me the questions and answers so far."

    init() {}

    func call(arguments _: GmAgentRpirGetClarificationArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_GET")
    }
}

@Generable
struct GmAgentRpirGetCarePackageArguments: Sendable {
    @Guide(description: promptUuidGuide("'s care package to read"))
    var promptUuid: String

    @Guide(
        description: """
            Carry every curated exploration body inline. Say false to get the \
            intent plus a stub roster (title, path, excerpt, size) — the bodies \
            are what grow, and the roster is what fits.
            """
    )
    var includeRefBodies: Bool

    @Guide(
        description: """
            One exploration ref's uuid, from the stub roster, to read that \
            curated body in full while the rest stay stubs. Empty means none.
            """
    )
    var refUuid: String

    init(promptUuid: String, includeRefBodies: Bool = true, refUuid: String = "") {
        self.promptUuid = promptUuid
        self.includeRefBodies = includeRefBodies
        self.refUuid = refUuid
    }
}

/// The care package on its own — the clarified intent, its refs, and the
/// curated exploration copies — narrowable to a stub roster and one body at a
/// time. The same shape `rpir_get_architecture` uses for options and change
/// rows, and the door `rpir_get_clarification`'s overflow retry points at.
struct GmAgentRpirGetCarePackageTool: GmAgentRpirTool {
    let name = "rpir_get_care_package"
    let description = "Show me the box on its own, one item at a time if it is big."

    init() {}

    func call(arguments _: GmAgentRpirGetCarePackageArguments) throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_GET")
    }
}
