import Foundation
import FoundationModels
import GmDaemonSdk

// The clarification family and the care package.
//
// ONE COUPLING TO KNOW. `open_clarification` used to be unnecessary: the
// clarification summary appeared as a side effect of moving the prompt's status
// to `clarifying`. That status no longer exists, so the summary has to be opened
// deliberately — this tool is what replaces the side effect, not an addition
// beside it.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenClarificationArguments: Sendable {
    @Guide(description: "Which prompt to open questions for, by uuid.")
    public var promptUuid: String

    public init(promptUuid: String) {
        self.promptUuid = promptUuid
    }
}

/// Start the question list.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenClarificationTool: GmAgentCdeTool {
    public let name = "cde_open_clarification"
    public let description = "Start the question list."

    public init() {}

    public func call(arguments: GmAgentCdeOpenClarificationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_OPEN")
    }
}

/// One question for the human, with its options.
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
public struct GmAgentCdeWriteClarificationQuestionsArguments: Sendable {
    @Guide(description: "Which question list to write to, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Who is writing, for the record.")
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

/// Write down many questions for the human.
///
/// The nested `options` array is worth noting as precedent: it is ALREADY a
/// batch of child rows on the wire — `CLARIFY_QUESTION_ADD` takes
/// `options: [String]` and writes one option row each — so batching a child
/// collection inside its parent is an existing pattern here, not an invention of
/// this surface.
///
/// The questions themselves still loop, with the same partial-write hazard as
/// every other plural write in this package.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteClarificationQuestionsTool: GmAgentCdeTool {
    public let name = "cde_write_clarification_questions"
    public let description = "Write down many questions for the human."

    public init() {}

    public func call(
        arguments: GmAgentCdeWriteClarificationQuestionsArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_QUESTION_ADD (looped)")
    }
}

/// One internal note — for the record, never shown to the user as a question.
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
public struct GmAgentCdeWriteClarificationNotesArguments: Sendable {
    @Guide(description: "Which question list the notes belong to, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Who is writing, for the record.")
    public var agentName: String

    @Guide(description: "All the notes to write in one go.")
    public var notes: [GmAgentClarificationNote]

    public init(summaryUuid: String, agentName: String, notes: [GmAgentClarificationNote]) {
        self.summaryUuid = summaryUuid
        self.agentName = agentName
        self.notes = notes
    }
}

/// Write down many private notes.
///
/// Notes are what is SETTLED — decisions, constraints and corrections that need
/// recording but do not need asking. Questions are for what genuinely needs the
/// human. Writing a settled thing as a question wastes the one scarce resource
/// in the loop, which is the user's attention.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteClarificationNotesTool: GmAgentCdeTool {
    public let name = "cde_write_clarification_notes"
    public let description = "Write down many private notes."

    public init() {}

    public func call(
        arguments: GmAgentCdeWriteClarificationNotesArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_NOTE_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeAnswerClarificationQuestionArguments: Sendable {
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

/// Human said this.
///
/// Record the answer as given. When the human answers with something other than
/// the offered options — which is common and usually the most valuable answer —
/// `answerText` is the record and `selectedOptionUuids` stays empty. Do not
/// round a free-form answer to the nearest option.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeAnswerClarificationQuestionTool: GmAgentCdeTool {
    public let name = "cde_answer_clarification_question"
    public let description = "Human said this."

    public init() {}

    public func call(
        arguments: GmAgentCdeAnswerClarificationQuestionArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_ANSWER")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeFinalizeClarificationArguments: Sendable {
    @Guide(description: "Which question list to finish, by uuid.")
    public var summaryUuid: String

    @Guide(description: "Version of the list you read.")
    public var expectedVersion: Int

    public init(summaryUuid: String, expectedVersion: Int) {
        self.summaryUuid = summaryUuid
        self.expectedVersion = expectedVersion
    }
}

/// Questions all done.
///
/// A PURE GATE and nothing more. The prompt behind this surface describes
/// finalize as also writing the summarised intent and opening the care package;
/// on the wire those are three separate things, and the clarified intent belongs
/// to `close_care_package`, not here. They are kept separate because folding
/// them would make one call that half-fails leave two records disagreeing about
/// whether clarification finished.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeFinalizeClarificationTool: GmAgentCdeTool {
    public let name = "cde_finalize_clarification"
    public let description = "Questions all done."

    public init() {}

    public func call(
        arguments: GmAgentCdeFinalizeClarificationArguments
    ) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_FINALIZE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeOpenCarePackageArguments: Sendable {
    @Guide(description: "Which question list the box belongs to, by uuid.")
    public var summaryUuid: String

    public init(summaryUuid: String) {
        self.summaryUuid = summaryUuid
    }
}

/// Get an empty box ready for the next agent.
///
/// DERIVED. The prompt folds opening into `finalize_clarification`; on the wire
/// `CARE_PACKAGE_OPEN` is its own verb and has to be called before anything can
/// be put in the box.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeOpenCarePackageTool: GmAgentCdeTool {
    public let name = "cde_open_care_package"
    public let description = "Get an empty box ready for the next agent."

    public init() {}

    public func call(arguments: GmAgentCdeOpenCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_OPEN")
    }
}

/// One thing put in the care package.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCareRef: Sendable {
    @Guide(description: "What sort of thing this is.", .anyOf(["dope", "kbite", "exploration"]))
    public var kind: String

    @Guide(description: "For a dope ref: the dot-path CODE, never a uuid.")
    public var dopeCode: String

    @Guide(description: "For a kbite ref: the kbite file uuid.")
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
public struct GmAgentCdeWriteCarePackageArguments: Sendable {
    @Guide(description: "Which box to fill, by uuid.")
    public var packageUuid: String

    @Guide(description: "Everything to put in the box, in one go.")
    public var refs: [GmAgentCareRef]

    public init(packageUuid: String, refs: [GmAgentCareRef]) {
        self.packageUuid = packageUuid
        self.refs = refs
    }
}

/// Put the good bits in the box for the next agent.
///
/// Exploration refs are COPIES of findings already made, rewritten with more
/// intent for the agent who will read them next. They are never a fresh
/// exploration — the curation is the value, and re-exploring here would both
/// duplicate work and quietly produce a second, unranked set of findings that
/// nothing calibrated.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeWriteCarePackageTool: GmAgentCdeTool {
    public let name = "cde_write_care_package"
    public let description = "Put the good bits in the box for the next agent."

    public init() {}

    public func call(arguments: GmAgentCdeWriteCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_REF_ADD (looped)")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeCloseCarePackageArguments: Sendable {
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

/// Box is ready.
///
/// THE CLARIFIED INTENT LIVES ONLY HERE. It is never written back to the prompt
/// row, which keeps the prompt as what the human actually typed and this as what
/// it was understood to mean. Everything downstream reads the intent from the
/// package rather than re-deriving it from raw exploration — which is the entire
/// reason the package exists.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeCloseCarePackageTool: GmAgentCdeTool {
    public let name = "cde_close_care_package"
    public let description = "Box is ready."

    public init() {}

    public func call(arguments: GmAgentCdeCloseCarePackageArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CARE_PACKAGE_COMPLETE")
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentCdeGetClarificationArguments: Sendable {
    @Guide(description: "Which prompt's questions to read, by uuid.")
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

/// Show me the questions and answers so far.
///
/// DERIVED, and narrowed by `noteWeightMax` for the same reason every read here
/// is narrowed.
@available(GmAgentOs 1.0, *)
public struct GmAgentCdeGetClarificationTool: GmAgentCdeTool {
    public let name = "cde_get_clarification"
    public let description = "Show me the questions and answers so far."

    public init() {}

    public func call(arguments: GmAgentCdeGetClarificationArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "CLARIFY_GET")
    }
}
