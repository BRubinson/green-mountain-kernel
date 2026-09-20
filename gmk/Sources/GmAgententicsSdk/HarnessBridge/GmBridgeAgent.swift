import Foundation

@available(GmAgentOs 1.0, *)
extension GmBridgeAgent {

    /// The eight directive+instruction combos, one harness agent each.
    ///
    /// Descriptions are capped at ten words: the harness matches on this field
    /// when deciding whether to delegate, so it is a routing signal rather than
    /// documentation. Every tool an agent's instruction set names must be granted
    /// here — a withheld one yields no visible refusal, and the agent falls back
    /// to guessing a wire verb through BASH or goes idle holding none.
    public static let all: [File] = [
        file(
            .primarch,
            name: "primarch",
            description: "GMCC primary agent. Drives the prompt lifecycle. Never auto-delegate.",
            native: [.bash, .read, .write, .edit, .grep, .glob, .task, .webFetch, .webSearch],
            tools: [
                GmAgentTools.Cde.initialize,
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Cde.setStatus,
                GmAgentTools.Rpir.next,

                GmAgentTools.Rpir.openBriefing,
                GmAgentTools.Rpir.loadExplorationBrief,

                GmAgentTools.Rpir.openExploration,
                GmAgentTools.Rpir.getExploration,
                GmAgentTools.Rpir.rankExplorations,

                GmAgentTools.Rpir.openClarification,
                GmAgentTools.Rpir.getClarification,
                GmAgentTools.Rpir.getCarePackage,
                GmAgentTools.Rpir.answerClarificationQuestion,
                GmAgentTools.Rpir.sealClarification,
                GmAgentTools.Rpir.finalizeClarification,

                GmAgentTools.Rpir.openCarePackage,
                GmAgentTools.Rpir.writeCarePackage,
                GmAgentTools.Rpir.closeCarePackage,

                GmAgentTools.Rpir.openArchitecture,
                GmAgentTools.Rpir.openArchitectureOption,
                GmAgentTools.Rpir.getArchitecture,
                GmAgentTools.Rpir.decideArchitecture,
                GmAgentTools.Rpir.writeArchitecturePersistenceChanges,
                GmAgentTools.Rpir.writeArchitectureFieldChanges,
                GmAgentTools.Rpir.writeArchitectureGeneralChanges,
                GmAgentTools.Rpir.summarizeArchitecture,
                GmAgentTools.Rpir.proposeArchitecture,
                GmAgentTools.Rpir.approveArchitecture,
                GmAgentTools.Rpir.reviseArchitecture,

                GmAgentTools.Rpir.openReview,
                GmAgentTools.Rpir.getReview,
                GmAgentTools.Rpir.rankReviews,
                GmAgentTools.Rpir.resolveReviewFinding,
                GmAgentTools.Rpir.completeReview,

                GmAgentTools.Cde.searchFileChanges,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Dope.searchGlobal,
                GmAgentTools.Dope.updateSessionDope,
            ]
        ),
        file(
            .briefer,
            name: "briefer",
            description: "GMCC briefing agent. Writes the briefing ref set. Never auto-delegate.",
            model: .haiku,
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.openBriefing,
                GmAgentTools.Rpir.loadExplorationBrief,
                GmAgentTools.Rpir.writeBrief,
                GmAgentTools.Rpir.closeBrief,
                GmAgentTools.Cde.searchFileChanges,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Dope.searchGlobal,
                GmAgentTools.Kbite.search,
            ]
        ),
        file(
            .explorer,
            name: "code-explorer",
            description: "GMCC exploration agent. Writes its own findings. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.Rpir.next,
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.loadExplorationBrief,
                GmAgentTools.Rpir.openExploration,
                GmAgentTools.Rpir.writeExplorations,
                GmAgentTools.Rpir.completeExploration,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Dope.searchGlobal,
                GmAgentTools.Kbite.search,
            ]
        ),
        file(
            .intentClarifier,
            name: "clarifier",
            description: "GMCC clarification agent. Ranks findings, writes questions. Never auto-delegate.",
            native: [.read, .grep, .glob],
            tools: [
                GmAgentTools.Rpir.next,
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.getExploration,
                GmAgentTools.Rpir.rankExplorations,
                GmAgentTools.Rpir.completeExploration,
                GmAgentTools.Rpir.openExploration,
                GmAgentTools.Rpir.openClarification,
                GmAgentTools.Rpir.writeClarificationQuestions,
                GmAgentTools.Rpir.writeClarificationNotes,
                GmAgentTools.Rpir.openCarePackage,
                GmAgentTools.Rpir.writeCarePackage,
                GmAgentTools.Dope.searchSession,
            ]
        ),
        file(
            .architect,
            name: "code-architect",
            description: "GMCC architecture agent. Writes one architecture option. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob, .webFetch, .webSearch],
            tools: [
                GmAgentTools.Rpir.next,
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.loadExplorationBrief,
                GmAgentTools.Rpir.getClarification,
                GmAgentTools.Rpir.getCarePackage,
                GmAgentTools.Rpir.getExploration,
                GmAgentTools.Rpir.openArchitectureOption,
                GmAgentTools.Rpir.writeArchitecturePersistenceChanges,
                GmAgentTools.Rpir.writeArchitectureFieldChanges,
                GmAgentTools.Rpir.writeArchitectureGeneralChanges,
                GmAgentTools.Rpir.getArchitecture,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Kbite.search,
            ]
        ),
        file(
            .implementor,
            name: "implementor",
            description: "GMCC implementation agent. Expands approved architecture into changes. Never auto-delegate.",
            native: [.bash, .read, .write, .edit, .grep, .glob],
            tools: [
                GmAgentTools.Rpir.next,
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.loadExplorationBrief,
                GmAgentTools.Rpir.getArchitecture,
                GmAgentTools.Cde.searchFileChanges,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Kbite.search,
            ]
        ),
        file(
            .reviewer,
            name: "code-quality-reviewer",
            description: "GMCC review agent. Writes review finding rows. Never auto-delegate.",
            native: [.bash, .read, .grep, .glob],
            tools: [
                GmAgentTools.Cde.loadPrompt,
                GmAgentTools.Rpir.loadExplorationBrief,
                GmAgentTools.Rpir.getClarification,
                GmAgentTools.Rpir.getCarePackage,
                GmAgentTools.Rpir.getArchitecture,
                GmAgentTools.Cde.searchFileChanges,
                GmAgentTools.Rpir.openReview,
                GmAgentTools.Rpir.writeReviews,
                GmAgentTools.Rpir.getReview,
                GmAgentTools.Dope.searchSession,
                GmAgentTools.Kbite.search,
            ]
        ),
        file(
            .kbiteChewer,
            name: "kbite-chewer",
            description: "GMCC kbite agent. Chews maw resources. Never auto-delegate.",
            native: [.bash, .read, .write, .grep, .glob],
            tools: [
                GmAgentTools.Kbite.openMaw,
                GmAgentTools.Kbite.digest,
                GmAgentTools.Kbite.search,
            ]
        ),
    ]
}
