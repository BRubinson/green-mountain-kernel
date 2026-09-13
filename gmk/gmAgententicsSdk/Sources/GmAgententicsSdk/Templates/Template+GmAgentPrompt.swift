import Foundation


// The ASK layer: the general formats agents pass to each other at runtime, and
// the assembly that sends one.
//
// Everything here is a TURN, not a standing contract, and the distinction is
// load-bearing rather than tidy. A model obeys instructions over prompts, so
// anything carrying caller-supplied text — a uuid, a one-line target, a topic
// derived from the Endotherm's own words — has to arrive on this side of the
// line. The directive and the instruction are authored and fixed for the run;
// these have holes in them, and the holes are filled with values nobody
// authored. There is deliberately no builder here that takes a free-form blob
// and welds it onto a directive.
//
// THE DELIVERABLE LIVES HERE. "YOUR FINDINGS ARE THE DELIVERABLE" used to sit
// in the directive, which made it a fact about who an agent is. It is not — it
// is the terms of the ask, the thing the sender is owed back, and it belongs
// beside the parameters that shaped it.
//
// EVERY ASK IS DOWNWARD, and there is no ask of the Primarch here. There was
// one, and it was deleted rather than left to rot: the Primarch does not
// receive an ask, he receives the Endotherm, and a template pretending
// otherwise would put one more forwarding step between the will and the work.
// What replaced it is `toBase` — carried by all seven asks, saying once and
// permanently that the Primarch's directive is the Endotherm's desire, so no
// ask below has to re-establish its own authority.
//
// ONE RETURN SHAPE, not seven. `fromBase` is the receipt every agent answers
// in, and it is deliberately uniform: the Primarch reads seven of these in one
// stretch, and seven formats is six chances to miss the line that mattered.
//
// HOLES ARE `{snake_case}` and match the instruction set's Primary Parameters
// name for name. A hole left unfilled stays VISIBLE as `{name}` — silently
// blanking it would hand an agent a prompt that reads complete and names a uuid
// nobody supplied, where a surviving `{prompt_uuid}` is a bug you can see.
//
// THIS FILE USED TO BE TWO. `GmAgentCdePrompts` held the formats and
// `GmAgentPrompt` wrapped it, and the wrapper had become a pure passthrough —
// an identity `switch` mapping seven cases onto seven identical cases. Merging
// also retired the `Cde` infix, which existed ONLY to dodge the sealed
// archive's `GmAgentPrompts` in this module; the singular spelling was never
// taken.

enum GmAgentPrompt: String, CaseIterable {

    case briefer
    case explorer
    case intentClarifier
    case architect
    case implementor
    case reviewer
    case kbiteChewer

    /// The directive of the agent this ask is addressed to.
    var directive: GmAgentDirectives {
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

    /// The downward header every ask opens with.
    ///
    /// Uniform across every case ON PURPOSE — it is the one place the Primarch's
    /// authority is established, and a per-role variant would be a second place
    /// it could be established differently. Exposed per case anyway so a caller
    /// assembling an ask by hand reaches for the same base the enum does.
    var toBase: String { GM_AGENT_TO_SUB_AGENT_PROMPT }

    /// The receipt shape every ask closes with, and every agent answers in.
    var fromBase: String { GM_AGENT_FROM_SUB_AGENT_PROMPT }

    /// This role's own ask line — the single thing distinguishing one downward
    /// ask from another once both bases are stripped away.
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

    /// The role-specific middle: parameters, target, deliverable. Carries
    /// neither base and is not sendable on its own.
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

    /// The whole ask, every hole still open: downward base, this role's line,
    /// its body, the return shape. Read it and diff it here; send it filled.
    var text: String {
        """
        \(toBase)
        \(toPrefix)
        \(body)

        \(fromBase)
        """
    }

    /// The ask with its `{snake_case}` holes closed by `parameters`.
    ///
    /// Keys match the instruction set's Primary Parameters name for name. A key
    /// with no matching hole is ignored; a hole with no matching key stays
    /// visible, for the reason in the header.
    func text(filling parameters: [String: String]) -> String {
        parameters.reduce(into: text) { filled, pair in
            filled = filled.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    /// The holes this ask carries, sorted — what a sender must supply to send
    /// it complete.
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
