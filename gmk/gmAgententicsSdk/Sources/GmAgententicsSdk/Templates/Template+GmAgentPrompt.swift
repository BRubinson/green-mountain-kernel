// The per-invocation turn text sent to each agent role, with its parameter holes.

import Foundation

enum GmAgentPrompt: String, CaseIterable {

    case briefer
    case explorer
    case intentClarifier
    case architect
    case implementor
    case reviewer
    case kbiteChewer

    var directive: AgentGmkDirective {
        switch self {
        case .briefer: return .briefer
        case .explorer: return .explorer
        case .intentClarifier: return .intentClarifier
        case .architect: return .architect
        case .implementor: return .implementor
        case .reviewer: return .reviewer
        case .kbiteChewer: return .kbiteChewer
        }
    }

    var toBase: String { GM_AGENT_TO_SUB_AGENT_PROMPT }

    var fromBase: String { GM_AGENT_FROM_SUB_AGENT_PROMPT }

    var toPrefix: String {
        switch self {
        case .briefer: return "## ASK OF THE **BRIEFER**"
        case .explorer: return "## ASK OF THE **CDE EXPLORER**"
        case .intentClarifier: return "## ASK OF THE **CDE INTENT CLARIFIER**"
        case .architect: return "## ASK OF THE **CDE ARCHITECT**"
        case .implementor: return "## ASK OF THE **CDE IMPLEMENTOR**"
        case .reviewer: return "## ASK OF THE **CDE REVIEWER**"
        case .kbiteChewer: return "## ASK OF THE **KBITE CHEWER**"
        }
    }

    var body: String {
        switch self {
        case .briefer: return GM_AGENT_BRIEFER_PROMPT
        case .explorer: return GM_CDE_AGENT_EXPLORE_PROMPT
        case .intentClarifier: return GM_CDE_AGENT_INTENT_CLARIFIER_PROMPT
        case .architect: return GM_CDE_AGENT_ARCHITECT_PROMPT
        case .implementor: return GM_CDE_AGENT_IMPLEMENTOR_PROMPT
        case .reviewer: return GM_CDE_AGENT_REVIEWER_PROMPT
        case .kbiteChewer: return GM_AGENT_KBITE_CHEWER_PROMPT
        }
    }

    var text: String {
        """
        \(toBase)
        \(toPrefix)
        \(body)

        \(fromBase)
        """
    }

    func text(filling parameters: [String: String]) -> String {
        parameters.reduce(into: text) { filled, pair in
            filled = filled.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    var holes: [String] {
        let pattern = try? NSRegularExpression(pattern: "\\{([a-z0-9_]+)\\}")
        let ask = text
        let range = NSRange(ask.startIndex..<ask.endIndex, in: ask)
        let matches = pattern?.matches(in: ask, range: range) ?? []
        let names = matches.compactMap { match -> String? in
            guard let captured = Range(match.range(at: 1), in: ask) else { return nil }
            return String(ask[captured])
        }
        return Array(Set(names)).sorted()
    }
}

let GM_AGENT_TO_SUB_AGENT_PROMPT = """
    # Agent Ask
    **From:** the Primarch. His directive is the Endotherm's desire.
    """

let GM_AGENT_FROM_SUB_AGENT_PROMPT_HEADER = """
    # Agent Receipt
    **To:** the Primarch
    """

let GM_AGENT_FROM_SUB_AGENT_PROMPT = """
    \(GM_AGENT_FROM_SUB_AGENT_PROMPT_HEADER)
    **Answer in this shape and no other:**

    **Recorded:** what you wrote and where it can be read. Counts and uuids, not prose.
    **Withheld:** what you did not do, could not do, or deliberately left — every one of them spoken aloud. An empty section is you swearing nothing was skipped.
    **Judgement:** the one thing only you can say, that the record cannot say for you. Two sentences at most.

    **Receipt Orders:**
        1. Your deliverable is in the record. Do not retell it here — the Primarch reads rows, not recollections.
        2. Report what IS. A gilded receipt is heresy, and it is the Primarch who wears it when the Endotherm finds out.
        3. Brevity is obedience. What you spend here, the Endotherm pays for.
    """

let GM_AGENT_BRIEFER_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Briefing:** {briefing_uuid}
    **Step:** {step}

    **Topic:**
    {topic}

    **Deliverable:**
        1. A sealed briefing carrying all three ref lists — dope, kbites, file changes — with an empty list wherever you looked and found none.
        2. THE REF SET IS THE DELIVERABLE. Nothing you say in your receipt is read by anyone downstream.
        3. Someone is blocked on you right now. Be quick.
    """

let GM_CDE_AGENT_EXPLORE_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Briefing:** {briefing_uuid}
    **Exploration:** {explore_uuid}
    **Personality:** {personality}

    **Target:**
    {target}

    **Deliverable:**
        1. Your finding rows, each weighted by your own judgement, key files among them.
        2. Your own sealed summary, whose overview says what the findings add up to.
        3. YOUR FINDINGS ARE THE DELIVERABLE. A discovery that lives only in a message is a discovery nothing recorded.
    """

let GM_CDE_AGENT_INTENT_CLARIFIER_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Exploration:** {explore_uuid}
    **Clarification:** {clarify_uuid}

    **Target:**
    {target}

    **Deliverable:**
        1. One calibrated ranking over every explorer's findings at once.
        2. A sealed synthesis summary.
        3. The question suite — two to four real alternatives apiece, sharpest first — and the notes for everything you settled yourself.
        4. THE RANKED RECORD AND THE SUITE ARE THE DELIVERABLE.
    """

let GM_CDE_AGENT_ARCHITECT_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Architecture:** {arch_uuid}
    **Personality:** {personality}

    **Target:**
    {target}

    **Deliverable:**
        1. One option row: goal, approach, components, persistence delta, files, build sequence, acceptance criteria, trade-offs.
        2. Persistence first within it. The rest is built over that.
        3. YOUR OPTION ROW IS THE DELIVERABLE. A plan that lives only in a message is a plan nothing recorded.
    """

let GM_CDE_AGENT_IMPLEMENTOR_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Architecture:** {arch_uuid}

    **Your Change:**
    {change_description}

    **Deliverable:**
        1. The change, landed, in the files your change description names and nowhere else.
        2. The verification this repo requires, actually run.
        3. QUOTED OUTPUT IS THE PROOF. Paste what the machine said, not what you concluded from it.
    """

let GM_CDE_AGENT_REVIEWER_PROMPT = """
    **Prompt:** {prompt_uuid}
    **Review:** {review_uuid}
    **Personality:** {personality}

    **Target:**
    {target}

    **Deliverable:**
        1. Your finding rows, weighted, anchored to file and lines wherever they have a location.
        2. The verdict you would give, and anything you believe is already resolved.
        3. YOUR FINDINGS ARE THE DELIVERABLE. A complaint that lives only in a message is a complaint nothing recorded.
    """

let GM_AGENT_KBITE_CHEWER_PROMPT = """
    **KBite:** {kbite_name}
    **Crunchable:** {crunchable_name}
    **Axes:** {axis1} / {axis2}
    **Maw:** {maw_path}

    **Deliverable:**
        1. One chewed file, complete enough that the digest never opens the raw source again.
        2. Every file under the maw covered, every path resolving, every score defensible.
        3. THE CHEWED FILE IS THE DELIVERABLE. Nothing you say about it is ingested.
    """
