// The tool vocabulary described to agents in their instruction text.

import Foundation

/// Returns tool guide text for a prompt uuid parameter.
///
/// - Parameter tail: The contextual tail describing the prompt.
/// - Returns: The formatted guide text.
func promptUuidGuide(_ tail: String) -> String {
    "Which prompt \(tail), by uuid."
}

/// Returns tool guide text for a summary uuid parameter.
///
/// - Parameters:
///   - verb: The action verb.
///   - subject: The subject being acted upon.
/// - Returns: The formatted guide text.
func summaryUuidGuide(to verb: String, _ subject: String) -> String {
    "Which \(subject) to \(verb), by summary uuid."
}

let GM_TOOL_GUIDE_AGENT_NAME = "Who is writing, for the record."

let GM_TOOL_GUIDE_EXPECTED_VERSION = "Version of the list you read."

let GM_TOOL_GUIDE_SEARCH_QUERY =
    "Words to look for. Whole words match; misspellings find nothing."

let GM_TOOL_GUIDE_SEARCH_LIMIT = "How many hits to return, 1 to 500."

let GM_TOOL_GUIDE_AGENT_ID = "Your own agent id, so two agents cannot share one list."

let GM_TOOL_GUIDE_RATING_OPTIONAL = """
    How important, 0 is most important and 999 is ignore. Leave it out \
    unless you were told to rate; ranking is one reader's job.
    """

let GM_TOOL_GUIDE_MAX_RATING = """
    Only return findings this important or better, 0 to 999. Use a small \
    number to keep the answer short.
    """

let GM_TOOL_GUIDE_DOPE_CODE = """
    Dot-path CODES like `domain.entity.property`. Never uuids, never file paths.
    """

let GM_TOOL_GUIDE_KBITE_FILE_UUID = "Kbite file uuids, not codes and not paths."

let GM_TOOL_GUIDE_EMPTY_LIST_IS_AN_ANSWER = """
    An empty list means you looked and found none, which is an answer. An \
    omitted list is refused — absent is indistinguishable from never having looked.
    """

let GM_TOOL_GUIDE_VERSION_CONFLICT = """
    The version you based this write on. On a conflict, re-read, take the new \
    version and retry — that is a normal outcome, not a failure.
    """

let GM_TOOL_NOT_BUILT_SUFFIX = "NOT BUILT YET."

/// Returns a "not built yet" description for a feature.
///
/// - Parameter what: The feature being described.
/// - Returns: The description with the not-built suffix.
func notBuiltDescription(_ what: String) -> String {
    "\(what). \(GM_TOOL_NOT_BUILT_SUFFIX)"
}

let GM_TOOL_ANYOF_AGENT_TYPE = ExplorationAgentType.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_FINDING_KIND = ExplorationFindingKind.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_REVIEW_KIND = ReviewFindingKind.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_REVIEW_VERDICT = ReviewVerdict.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_PROMPT_STATUS = PromptStatus.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_CHANGE_DEPTH = ChangeDepth.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_CARE_REF_KIND = CarePackageRefKind.allCases.map(\.rawValue)

let GM_TOOL_ANYOF_REVIEW_RESOLUTION = ["fixed", "accepted", "wont_fix"]

let GM_TOOL_ANYOF_ARCH_CHANGE_KIND = ["add", "modify", "rename", "delete"]
