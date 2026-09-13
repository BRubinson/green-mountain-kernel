// The namespace that makes every GmAgentTool conformance reachable in one place.

import Foundation
import FoundationModels

@available(GmAgentOs 1.0, *)
public enum GmAgentTools {

    public enum dope {
        public static let searchGlobal = GmAgentDopeSearchGlobalTool()
        public static let searchSession = GmAgentDopeSearchSessionTool()
        public static let updateSessionDope = GmAgentDopeUpdateSessionTool()

        public static let all: [any GmAgentTool] = [
            searchGlobal, searchSession, updateSessionDope,
        ]
    }

    public enum kbite {
        public static let search = GmAgentKbiteSearchTool()
        public static let openMaw = GmAgentKbiteOpenMawTool()
        public static let digest = GmAgentKbiteDigestTool()

        public static let all: [any GmAgentTool] = [search, openMaw, digest]
    }

    public enum diagram {
        public static let notSupported = GmAgentDiagramPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum projects {
        public static let search = GmAgentProjectsSearchTool()
        public static let updateSession = GmAgentProjectsUpdateSessionTool()

        public static let all: [any GmAgentTool] = [search, updateSession]
    }

    public enum system {
        public static let notSupported = GmAgentSystemPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum fs {
        public static let notSupported = GmAgentFsPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum cde {

        public static let initialize = GmAgentCdeInitTool()
        public static let loadPrompt = GmAgentCdeLoadPromptTool()
        public static let setStatus = GmAgentCdeSetStatusTool()
        public static let next = GmAgentCdeNextTool()

        public static let openBriefing = GmAgentCdeOpenBriefingTool()
        public static let writeBrief = GmAgentCdeWriteBriefTool()
        public static let closeBrief = GmAgentCdeCloseBriefTool()
        public static let loadExplorationBrief = GmAgentCdeLoadBriefTool()

        public static let openExploration = GmAgentCdeOpenExplorationTool()
        public static let writeExplorations = GmAgentCdeWriteExplorationsTool()
        public static let rankExplorations = GmAgentCdeRankExplorationsTool()
        public static let completeExploration = GmAgentCdeCompleteExplorationTool()
        public static let getExploration = GmAgentCdeGetExplorationTool()

        public static let openClarification = GmAgentCdeOpenClarificationTool()
        public static let writeClarificationQuestions =
            GmAgentCdeWriteClarificationQuestionsTool()
        public static let writeClarificationNotes = GmAgentCdeWriteClarificationNotesTool()
        public static let answerClarificationQuestion =
            GmAgentCdeAnswerClarificationQuestionTool()
        public static let finalizeClarification = GmAgentCdeFinalizeClarificationTool()
        public static let openCarePackage = GmAgentCdeOpenCarePackageTool()
        public static let writeCarePackage = GmAgentCdeWriteCarePackageTool()
        public static let closeCarePackage = GmAgentCdeCloseCarePackageTool()
        public static let getClarification = GmAgentCdeGetClarificationTool()

        public static let openArchitectureOption = GmAgentCdeOpenArchitectureOptionTool()
        public static let writeArchitecturePersistenceChanges =
            GmAgentCdeWriteArchitecturePersistenceChangesTool()
        public static let writeArchitectureGeneralChanges =
            GmAgentCdeWriteArchitectureGeneralChangesTool()
        public static let decideArchitecture = GmAgentCdeDecideArchitectureTool()
        public static let getArchitecture = GmAgentCdeGetArchitectureTool()

        public static let openReview = GmAgentCdeOpenReviewTool()
        public static let writeReviews = GmAgentCdeWriteReviewsTool()
        public static let rankReviews = GmAgentCdeRankReviewsTool()
        public static let completeReview = GmAgentCdeCompleteReviewTool()
        public static let resolveReviewFinding = GmAgentCdeResolveReviewFindingTool()
        public static let getReview = GmAgentCdeGetReviewTool()

        public static let searchExploration = GmAgentCdeSearchExplorationTool()
        public static let searchClarification = GmAgentCdeSearchClarificationTool()
        public static let searchArchitecture = GmAgentCdeSearchArchitectureTool()
        public static let searchArchitectureOption = GmAgentCdeSearchArchitectureOptionTool()
        public static let searchReview = GmAgentCdeSearchReviewTool()
        public static let searchFileChanges = GmAgentCdeSearchFileChangesTool()

        public static let all: [any GmAgentTool] = [
            initialize, loadPrompt, setStatus, next,
            openBriefing, writeBrief, closeBrief, loadExplorationBrief,
            openExploration, writeExplorations, rankExplorations, completeExploration,
            getExploration,
            openClarification, writeClarificationQuestions, writeClarificationNotes,
            answerClarificationQuestion, finalizeClarification,
            openCarePackage, writeCarePackage, closeCarePackage, getClarification,
            openArchitectureOption, writeArchitecturePersistenceChanges,
            writeArchitectureGeneralChanges, decideArchitecture, getArchitecture,
            openReview, writeReviews, rankReviews, completeReview, resolveReviewFinding,
            getReview,
            searchExploration, searchClarification, searchArchitecture,
            searchArchitectureOption, searchReview, searchFileChanges,
        ]
    }

    public static let all: [any GmAgentTool] =
        dope.all + kbite.all + diagram.all + cde.all + projects.all + system.all + fs.all

    public static func tools(in family: GmAgentToolFamily) -> [any GmAgentTool] {
        switch family {
        case .dope: return dope.all
        case .kbite: return kbite.all
        case .diagram: return diagram.all
        case .cde: return cde.all
        case .projects: return projects.all
        case .system: return system.all
        case .fs: return fs.all
        }
    }
}
