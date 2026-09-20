// The namespace that makes every GmAgentTool conformance reachable in one place.

import Foundation
import FoundationModels

public enum GmAgentTools {

    public enum Dope {
        public static let searchGlobal = GmAgentDopeSearchGlobalTool()
        public static let searchSession = GmAgentDopeSearchSessionTool()
        public static let updateSessionDope = GmAgentDopeUpdateSessionTool()

        public static let all: [any GmAgentTool] = [
            searchGlobal, searchSession, updateSessionDope,
        ]
    }

    public enum Kbite {
        public static let search = GmAgentKbiteSearchTool()
        public static let openMaw = GmAgentKbiteOpenMawTool()
        public static let digest = GmAgentKbiteDigestTool()

        public static let all: [any GmAgentTool] = [search, openMaw, digest]
    }

    public enum Diagram {
        public static let notSupported = GmAgentDiagramPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum Projects {
        public static let search = GmAgentProjectsSearchTool()
        public static let updateSession = GmAgentProjectsUpdateSessionTool()

        public static let all: [any GmAgentTool] = [search, updateSession]
    }

    public enum System {
        public static let notSupported = GmAgentSystemPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum Fs {
        public static let notSupported = GmAgentFsPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    public enum Cde {

        public static let initialize = GmAgentCdeInitTool()
        public static let loadPrompt = GmAgentCdeLoadPromptTool()
        public static let setStatus = GmAgentCdeSetStatusTool()
        public static let searchFileChanges = GmAgentCdeSearchFileChangesTool()

        public static let all: [any GmAgentTool] = [
            initialize, loadPrompt, setStatus, searchFileChanges,
        ]
    }

    public enum Rpir {

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
        public static let getCarePackage = GmAgentRpirGetCarePackageTool()

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
            getCarePackage,
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
        Dope.all + Kbite.all + Diagram.all + Cde.all + Rpir.all + Projects.all
        + System.all + Fs.all

    public static func tools(in family: GmAgentToolFamily) -> [any GmAgentTool] {
        switch family {
        case .dope: return Dope.all
        case .kbite: return Kbite.all
        case .diagram: return Diagram.all
        case .cde: return Cde.all
        case .rpir: return Rpir.all
        case .projects: return Projects.all
        case .system: return System.all
        case .fs: return Fs.all
        }
    }
}
