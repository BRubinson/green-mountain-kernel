// Agent tools for the clarification phase: questions, notes, answers and the care package.

import Foundation
import FoundationModels
import GmDaemonSdk

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirOpenClarificationArguments: Sendable {
    @Guide(description: promptUuidGuide("to open questions for"))
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirOpenClarificationTool: GmAgentRpirTool {
    public let name = "rpir_open_clarification"
    public let description = "Start the question list."

    public init() {}

    public func call(arguments: GmAgentRpirOpenClarificationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentClarificationQuestion: Sendable {
    @Guide(description: "The question, written so a human can answer it without reading code.")
    public var question: String

    @Guide(description: """
        The answers to offer, in order. Write real alternatives with their \
        trade-offs, not yes/no.
        """)
    public var options: [String]

    public init(question: String, options: [String] = []) {
        self.question = question
        self.options = options
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWriteClarificationQuestionsArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "write to", "question list"))
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    public var agentName: String

    @Guide(description: "All the questions to write in one go.")
    public var questions: [GmAgentClarificationQuestion]

    public init(
        summaryUuid: String, agentName: String, questions: [GmAgentClarificationQuestion]
    ) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.questions = questions
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteClarificationQuestionsTool: GmAgentRpirTool {
    public let name = "rpir_write_clarification_questions"
    public let description = "Write down many questions for the human."

    public init() {}

    public func call(
        arguments: GmAgentRpirWriteClarificationQuestionsArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_QUESTION_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentClarificationNote: Sendable {
    @Guide(description: "The note.")
    public var body: String

    @Guide(description: "How important: 0 is critical, 999 is ignore.", .range(0...999))
    public var weight: Int

    public init(body: String, weight: Int = 100) {
        self.body = body
        self.weight = weight
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWriteClarificationNotesArguments: Sendable {
    @Guide(description: "Which question list the notes belong to, by uuid.")
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_AGENT_NAME)
    public var agentName: String

    @Guide(description: "All the notes to write in one go.")
    public var notes: [GmAgentClarificationNote]

    public init(summaryUuid: String, agentName: String, notes: [GmAgentClarificationNote]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.notes = notes
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteClarificationNotesTool: GmAgentRpirTool {
    public let name = "rpir_write_clarification_notes"
    public let description = "Write down many private notes."

    public init() {}

    public func call(
        arguments: GmAgentRpirWriteClarificationNotesArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_NOTE_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirAnswerClarificationQuestionArguments: Sendable {
    @Guide(description: "Which question was answered, by uuid.")
    public var questionUuid: String

    @Guide(description: "Version of the question you read.")
    public var expectedVersion: Int

    @Guide(description: "What the human said, in their words.")
    public var answerText: String

    @Guide(description: "Which offered options they picked, by uuid.")
    public var selectedOptionUuids: [String]

    @Guide(description: "True if they declined to answer.")
    public var skip: Bool

    public init(
        questionUuid: String, expectedVersion: Int, answerText: String,
        selectedOptionUuids: [String] = [], skip: Bool = false
    ) {
        self.questionUuid = questionUuid
        self.expectedVersion = expectedVersion
        self.answerText = answerText
        self.selectedOptionUuids = selectedOptionUuids
        self.skip = skip
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirAnswerClarificationQuestionTool: GmAgentRpirTool {
    public let name = "rpir_answer_clarification_question"
    public let description = "Human said this."

    public init() {}

    public func call(
        arguments: GmAgentRpirAnswerClarificationQuestionArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_ANSWER")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirFinalizeClarificationArguments: Sendable {
    @Guide(description: summaryUuidGuide(to: "finish", "question list"))
    public var summaryUuid: String

    @Guide(description: GM_TOOL_GUIDE_EXPECTED_VERSION)
    public var expectedVersion: Int

    public init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirFinalizeClarificationTool: GmAgentRpirTool {
    public let name = "rpir_finalize_clarification"
    public let description = "Questions all done."

    public init() {}

    public func call(
        arguments: GmAgentRpirFinalizeClarificationArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_FINALIZE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirOpenCarePackageArguments: Sendable {
    @Guide(description: "Which question list the box belongs to, by uuid.")
    public var summaryUuid: String

    public init(summaryUuid: String) {
        self.summaryUuid = summaryUuid
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirOpenCarePackageTool: GmAgentRpirTool {
    public let name = "rpir_open_care_package"
    public let description = "Get an empty box ready for the next agent."

    public init() {}

    public func call(arguments: GmAgentRpirOpenCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_OPEN")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCareRef: Sendable {
    @Guide(description: "What sort of thing this is.", .anyOf(GM_TOOL_ANYOF_CARE_REF_KIND))
    public var kind: String

    @Guide(description: "For a dope ref. " + GM_TOOL_GUIDE_DOPE_CODE)
    public var dopeCode: String

    @Guide(description: "For a kbite ref. " + GM_TOOL_GUIDE_KBITE_FILE_UUID)
    public var kbiteFileUuid: String

    @Guide(description: "For an exploration ref: a title for the copied finding.")
    public var title: String

    @Guide(description: """
        For an exploration ref: the finding written out again with more intent. \
        Copy and sharpen what was already found — do not go exploring again.
        """)
    public var body: String

    public init(
        kind: String, dopeCode: String = "", kbiteFileUuid: String = "",
        title: String = "", body: String = ""
    ) {
        self.kind = kind
        self.dopeCode = dopeCode
        self.kbiteFileUuid = kbiteFileUuid
        self.title = title
        self.body = body
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirWriteCarePackageArguments: Sendable {
    @Guide(description: "Which box to fill, by uuid.")
    public var packageUuid: String

    @Guide(description: "Everything to put in the box, in one go.")
    public var refs: [GmAgentCareRef]

    public init(packageUuid: String, refs: [GmAgentCareRef]) {
        self.packageUuid = packageUuid
        self.refs = refs
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirWriteCarePackageTool: GmAgentRpirTool {
    public let name = "rpir_write_care_package"
    public let description = "Put the good bits in the box for the next agent."

    public init() {}

    public func call(arguments: GmAgentRpirWriteCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_REF_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirCloseCarePackageArguments: Sendable {
    @Guide(description: "Which box to seal, by uuid.")
    public var packageUuid: String

    @Guide(description: "Version of the box you read.")
    public var expectedVersion: Int

    @Guide(description: """
        What was decided, in full: what was chosen, and what was ruled out and \
        why. This is the only place it is written down.
        """)
    public var clarifiedIntent: String

    public init(packageUuid: String, expectedVersion: Int, clarifiedIntent: String) {
        self.packageUuid = packageUuid
        self.expectedVersion = expectedVersion
        self.clarifiedIntent = clarifiedIntent
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirCloseCarePackageTool: GmAgentRpirTool {
    public let name = "rpir_close_care_package"
    public let description = "Box is ready."

    public init() {}

    public func call(arguments: GmAgentRpirCloseCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentRpirGetClarificationArguments: Sendable {
    @Guide(description: promptUuidGuide("'s questions to read"))
    public var promptUuid: String

    @Guide(description: """
        Only return notes this important or better, 0 to 999. Use a small \
        number to keep the answer short.
        """, .range(0...999))
    public var noteWeightMax: Int

    public init(promptUuid: String, noteWeightMax: Int = 100) {
        self.promptUuid = promptUuid
        self.noteWeightMax = noteWeightMax
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentRpirGetClarificationTool: GmAgentRpirTool {
    public let name = "rpir_get_clarification"
    public let description = "Show me the questions and answers so far."

    public init() {}

    public func call(arguments: GmAgentRpirGetClarificationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_GET")
    }
}
