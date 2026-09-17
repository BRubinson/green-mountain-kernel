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
        public static let searchFileChanges = GmAgentCdeSearchFileChangesTool()

        public static let all: [any GmAgentTool] = [
            initialize, loadPrompt, setStatus, searchFileChanges,
        ]
    }

    public enum rpir {

        public static let next = GmAgentRpirNextTool()

        public static let openBriefing = GmAgentRpirOpenBriefingTool()
        public static let writeBrief = GmAgentRpirWriteBriefTool()
        public static let closeBrief = GmAgentRpirCloseBriefTool()
        public static let loadExplorationBrief = GmAgentRpirLoadBriefTool()

        public static let openExploration = GmAgentRpirOpenExplorationTool()
        public static let writeExplorations = GmAgentRpirWriteExplorationsTool()
        public static let rankExplorations = GmAgentRpirRankExplorationsTool()
        public static let completeExploration = GmAgentRpirCompleteExplorationTool()
        public static let getExploration = GmAgentRpirGetExplorationTool()

        public static let openClarification = GmAgentRpirOpenClarificationTool()
        public static let writeClarificationQuestions =
            GmAgentRpirWriteClarificationQuestionsTool()
        public static let writeClarificationNotes = GmAgentRpirWriteClarificationNotesTool()
        public static let answerClarificationQuestion =
            GmAgentRpirAnswerClarificationQuestionTool()
        public static let sealClarification = GmAgentRpirSealClarificationTool()
        public static let finalizeClarification = GmAgentRpirFinalizeClarificationTool()
        public static let openCarePackage = GmAgentRpirOpenCarePackageTool()
        public static let writeCarePackage = GmAgentRpirWriteCarePackageTool()
        public static let closeCarePackage = GmAgentRpirCloseCarePackageTool()
        public static let getClarification = GmAgentRpirGetClarificationTool()

        public static let openArchitecture = GmAgentRpirOpenArchitectureTool()
        public static let openArchitectureOption = GmAgentRpirOpenArchitectureOptionTool()
        public static let writeArchitecturePersistenceChanges =
            GmAgentRpirWriteArchitecturePersistenceChangesTool()
        public static let writeArchitectureFieldChanges =
            GmAgentRpirWriteArchitectureFieldChangesTool()
        public static let writeArchitectureGeneralChanges =
            GmAgentRpirWriteArchitectureGeneralChangesTool()
        public static let summarizeArchitecture = GmAgentRpirSummarizeArchitectureTool()
        public static let proposeArchitecture = GmAgentRpirProposeArchitectureTool()
        public static let approveArchitecture = GmAgentRpirApproveArchitectureTool()
        public static let reviseArchitecture = GmAgentRpirReviseArchitectureTool()
        public static let decideArchitecture = GmAgentRpirDecideArchitectureTool()
        public static let getArchitecture = GmAgentRpirGetArchitectureTool()

        public static let openReview = GmAgentRpirOpenReviewTool()
        public static let writeReviews = GmAgentRpirWriteReviewsTool()
        public static let rankReviews = GmAgentRpirRankReviewsTool()
        public static let completeReview = GmAgentRpirCompleteReviewTool()
        public static let resolveReviewFinding = GmAgentRpirResolveReviewFindingTool()
        public static let getReview = GmAgentRpirGetReviewTool()

        public static let searchExploration = GmAgentRpirSearchExplorationTool()
        public static let searchClarification = GmAgentRpirSearchClarificationTool()
        public static let searchArchitecture = GmAgentRpirSearchArchitectureTool()
        public static let searchArchitectureOption = GmAgentRpirSearchArchitectureOptionTool()
        public static let searchReview = GmAgentRpirSearchReviewTool()

        public static let all: [any GmAgentTool] = [
            next,
            openBriefing, writeBrief, closeBrief, loadExplorationBrief,
            openExploration, writeExplorations, rankExplorations, completeExploration,
            getExploration,
            openClarification, writeClarificationQuestions, writeClarificationNotes,
            answerClarificationQuestion, sealClarification, finalizeClarification,
            openCarePackage, writeCarePackage, closeCarePackage, getClarification,
            openArchitecture, openArchitectureOption, writeArchitecturePersistenceChanges,
            writeArchitectureFieldChanges, writeArchitectureGeneralChanges,
            summarizeArchitecture, proposeArchitecture, approveArchitecture,
            reviseArchitecture, decideArchitecture, getArchitecture,
            openReview, writeReviews, rankReviews, completeReview, resolveReviewFinding,
            getReview,
            searchExploration, searchClarification, searchArchitecture,
            searchArchitectureOption, searchReview,
        ]
    }

    public static let all: [any GmAgentTool] =
        dope.all + kbite.all + diagram.all + cde.all + rpir.all + projects.all
        + system.all + fs.all

    public static func tools(in family: GmAgentToolFamily) -> [any GmAgentTool] {
        switch family {
        case .dope: return dope.all
        case .kbite: return kbite.all
        case .diagram: return diagram.all
        case .cde: return cde.all
        case .rpir: return rpir.all
        case .projects: return projects.all
        case .system: return system.all
        case .fs: return fs.all
        }
    }
}
