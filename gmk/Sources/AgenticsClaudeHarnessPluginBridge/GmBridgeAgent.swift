import Foundation

extension GmBridgeAgent {

    /// The eight directive+instruction combos, one harness agent each.
    ///
    /// Descriptions are capped at ten words: the harness matches on this field
    /// when deciding whether to delegate. Every tool an agent's instruction set
    /// names must be granted here — a withheld one yields no visible refusal.
    /// A grant is per TOOL, never per op, so which ops belong to the primary is
    /// guidance carried by the agent body and `CdeSheet`.
    static let all: [File] = [
        // No model pin: the primarch drives the session the Endotherm already
        // chose a model for.
        file(
            .primarch,
            name: "primarch",
            description: "GMCC primary agent. Drives the prompt lifecycle. Never auto-delegate.",
            native: [.bash, .read, .write, .edit, .grep, .glob, .task, .webFetch, .webSearch],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeSession,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeRpirExplore,
                GmAgentTools.cdeRpirClarify,
                GmAgentTools.cdeRpirArchitecture,
                GmAgentTools.cdeRpirReview,
                GmAgentTools.cdeRpirSearch,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .briefer,
            name: "briefer",
            description: "GMCC briefing agent. Writes the briefing ref set. Never auto-delegate.",
            model: .opus,
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .explorer,
            name: "code-explorer",
            description: "GMCC exploration agent. Writes its own findings. Never auto-delegate.",
            model: .opus,
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeRpirExplore,
                GmAgentTools.cdeRpirSearch,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .intentClarifier,
            name: "clarifier",
            description: "GMCC clarification agent. Ranks findings, writes questions. Never auto-delegate.",
            model: .opus,
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirExplore,
                GmAgentTools.cdeRpirClarify,
                GmAgentTools.cdeRpirSearch,
                GmAgentTools.cdeDope,
            ]
        ),
        file(
            .architect,
            name: "code-architect",
            description: "GMCC architecture agent. Writes one architecture option. Never auto-delegate.",
            model: .opus,
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeRpirClarify,
                GmAgentTools.cdeRpirExplore,
                GmAgentTools.cdeRpirArchitecture,
                GmAgentTools.cdeRpirSearch,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .implementor,
            name: "implementor",
            description: "GMCC implementation agent. Expands approved architecture into changes. Never auto-delegate.",
            model: .opus,
            native: [.bash, .read, .write, .edit, .grep, .glob],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeRpirArchitecture,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .reviewer,
            name: "code-quality-reviewer",
            description: "GMCC review agent. Writes review finding rows. Never auto-delegate.",
            model: .opus,
            native: [.bash, .read, .grep, .glob],
            tools: [
                GmAgentTools.cdeInit,
                GmAgentTools.cdePrompt,
                GmAgentTools.cdeRpirBriefing,
                GmAgentTools.cdeRpirClarify,
                GmAgentTools.cdeRpirArchitecture,
                GmAgentTools.cdeRpirReview,
                GmAgentTools.cdeRpirSearch,
                GmAgentTools.cdeDope,
                GmAgentTools.cdeKbite,
            ]
        ),
        file(
            .kbiteChewer,
            name: "kbite-chewer",
            description: "GMCC kbite agent. Chews maw resources. Never auto-delegate.",
            model: .opus,
            native: [.bash, .read, .write, .grep, .glob],
            tools: [GmAgentTools.cdeKbite]
        ),
    ]
}
