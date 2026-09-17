import Foundation

@available(GmAgentOs 1.0, *)
extension GmBridgeAgent {

    /// The eight directive+instruction combos, one harness agent each.
    ///
    /// Descriptions are capped at ten words because this field is what the
    /// harness matches on when deciding whether to delegate — it is a routing
    /// signal, not documentation. "Never auto-delegate" is the load-bearing half
    /// of every workflow agent's line: these are spawned by the phase machine,
    /// and each carries only the tools its one phase needs — except the
    /// primarch, which walks every phase.
    ///
    /// THE RULE: every tool an agent's instruction set names is granted here.
    /// A withheld one yields no visible refusal — the agent falls back to
    /// guessing a wire verb through BASH, or, holding no BASH, goes idle.
    public static let all: [File] = [
        file(
            .primarch,
            name: "primarch",
            description: "GMCC primary agent. Drives the prompt lifecycle. Never auto-delegate.",
            native: [.bash, .read, .write, .edit, .grep, .glob, .task, .webFetch, .webSearch],
            tools: [
                GmAgentTools.cde.initialize,
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.cde.setStatus,
                GmAgentTools.rpir.next,

                GmAgentTools.rpir.openBriefing,
                GmAgentTools.rpir.loadExplorationBrief,

                GmAgentTools.rpir.openExploration,
                GmAgentTools.rpir.getExploration,
                GmAgentTools.rpir.rankExplorations,

                GmAgentTools.rpir.openClarification,
                GmAgentTools.rpir.getClarification,
                GmAgentTools.rpir.answerClarificationQuestion,
                GmAgentTools.rpir.sealClarification,
                GmAgentTools.rpir.finalizeClarification,

                GmAgentTools.rpir.openCarePackage,
                GmAgentTools.rpir.writeCarePackage,
                GmAgentTools.rpir.closeCarePackage,

                GmAgentTools.rpir.openArchitecture,
                GmAgentTools.rpir.openArchitectureOption,
                GmAgentTools.rpir.getArchitecture,
                GmAgentTools.rpir.decideArchitecture,
                GmAgentTools.rpir.writeArchitecturePersistenceChanges,
                GmAgentTools.rpir.writeArchitectureFieldChanges,
                GmAgentTools.rpir.writeArchitectureGeneralChanges,
                GmAgentTools.rpir.summarizeArchitecture,
                GmAgentTools.rpir.proposeArchitecture,
                GmAgentTools.rpir.approveArchitecture,
                GmAgentTools.rpir.reviseArchitecture,

                GmAgentTools.rpir.openReview,
                GmAgentTools.rpir.getReview,
                GmAgentTools.rpir.rankReviews,
                GmAgentTools.rpir.resolveReviewFinding,
                GmAgentTools.rpir.completeReview,

                GmAgentTools.cde.searchFileChanges,
                GmAgentTools.dope.searchSession,
                GmAgentTools.dope.searchGlobal,
                GmAgentTools.dope.updateSessionDope,
            ]
        ),
        file(
            .briefer,
            name: "briefer",
            description: "GMCC briefing agent. Writes the briefing ref set. Never auto-delegate.",
            model: .haiku,
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.openBriefing,
                GmAgentTools.rpir.loadExplorationBrief,
                GmAgentTools.rpir.writeBrief,
                GmAgentTools.rpir.closeBrief,
                GmAgentTools.cde.searchFileChanges,
                GmAgentTools.dope.searchSession,
                GmAgentTools.dope.searchGlobal,
                GmAgentTools.kbite.search,
            ]
        ),
        file(
            .explorer,
            name: "code-explorer",
            description: "GMCC exploration agent. Writes its own findings. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.rpir.next,
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.loadExplorationBrief,
                GmAgentTools.rpir.openExploration,
                GmAgentTools.rpir.writeExplorations,
                GmAgentTools.rpir.completeExploration,
                GmAgentTools.dope.searchSession,
                GmAgentTools.dope.searchGlobal,
                GmAgentTools.kbite.search,
            ]
        ),
        file(
            .intentClarifier,
            name: "clarifier",
            description: "GMCC clarification agent. Ranks findings, writes questions. Never auto-delegate.",
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.rpir.next,
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.getExploration,
                GmAgentTools.rpir.rankExplorations,
                GmAgentTools.rpir.completeExploration,
                GmAgentTools.rpir.openExploration,
                GmAgentTools.rpir.openClarification,
                GmAgentTools.rpir.writeClarificationQuestions,
                GmAgentTools.rpir.writeClarificationNotes,
                GmAgentTools.dope.searchSession,
            ]
        ),
        file(
            .architect,
            name: "code-architect",
            description: "GMCC architecture agent. Writes one architecture option. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.rpir.next,
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.loadExplorationBrief,
                GmAgentTools.rpir.getClarification,
                GmAgentTools.rpir.getExploration,
                GmAgentTools.rpir.openArchitectureOption,
                GmAgentTools.rpir.writeArchitecturePersistenceChanges,
                GmAgentTools.rpir.writeArchitectureFieldChanges,
                GmAgentTools.rpir.writeArchitectureGeneralChanges,
                GmAgentTools.rpir.getArchitecture,
                GmAgentTools.dope.searchSession,
                GmAgentTools.kbite.search,
            ]
        ),
        file(
            .implementor,
            name: "implementor",
            description: "GMCC implementation agent. Expands approved architecture into changes. Never auto-delegate.",
            native: [.bash, .read, .write, .edit, .grep, .glob],
            tools: [
                GmAgentTools.rpir.next,
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.loadExplorationBrief,
                GmAgentTools.rpir.getArchitecture,
                GmAgentTools.cde.searchFileChanges,
                GmAgentTools.dope.searchSession,
                GmAgentTools.kbite.search,
            ]
        ),
        file(
            .reviewer,
            name: "code-quality-reviewer",
            description: "GMCC review agent. Writes review finding rows. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob],
            tools: [
                GmAgentTools.cde.loadPrompt,
                GmAgentTools.rpir.loadExplorationBrief,
                GmAgentTools.rpir.getClarification,
                GmAgentTools.rpir.getArchitecture,
                GmAgentTools.cde.searchFileChanges,
                GmAgentTools.rpir.openReview,
                GmAgentTools.rpir.writeReviews,
                GmAgentTools.rpir.getReview,
                GmAgentTools.dope.searchSession,
                GmAgentTools.kbite.search,
            ]
        ),
        file(
            .kbiteChewer,
            name: "kbite-chewer",
            description: "GMCC kbite agent. Chews maw resources. Never auto-delegate.",
            native: [.bash, .read, .write, .grep, .glob],
            tools: [
                GmAgentTools.kbite.openMaw,
                GmAgentTools.kbite.digest,
                GmAgentTools.kbite.search,
            ]
        ),
    ]
}
