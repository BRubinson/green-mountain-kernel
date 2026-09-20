// The namespace that makes every GmAgentTool conformance reachable in one place.

import Foundation
import FoundationModels

enum GmAgentTools {

    enum Dope {
        static let searchGlobal = GmAgentDopeSearchGlobalTool()
        static let searchSession = GmAgentDopeSearchSessionTool()
        static let updateSessionDope = GmAgentDopeUpdateSessionTool()

        static let all: [any GmAgentTool] = [
            searchGlobal, searchSession, updateSessionDope,
        ]
    }

    enum Kbite {
        static let search = GmAgentKbiteSearchTool()
        static let openMaw = GmAgentKbiteOpenMawTool()
        static let digest = GmAgentKbiteDigestTool()

        static let all: [any GmAgentTool] = [search, openMaw, digest]
    }

    enum Diagram {
        static let notSupported = GmAgentDiagramPlaceholderTool()

        static let all: [any GmAgentTool] = [notSupported]
    }

    enum Projects {
        static let search = GmAgentProjectsSearchTool()
        static let updateSession = GmAgentProjectsUpdateSessionTool()

        static let all: [any GmAgentTool] = [search, updateSession]
    }

    enum System {
        static let notSupported = GmAgentSystemPlaceholderTool()

        static let all: [any GmAgentTool] = [notSupported]
    }

    enum Fs {
        static let notSupported = GmAgentFsPlaceholderTool()

        static let all: [any GmAgentTool] = [notSupported]
    }

    enum Cde {

        static let initialize = GmAgentCdeInitTool()
        static let loadPrompt = GmAgentCdeLoadPromptTool()
        static let setStatus = GmAgentCdeSetStatusTool()
        static let searchFileChanges = GmAgentCdeSearchFileChangesTool()

        static let all: [any GmAgentTool] = [
            initialize, loadPrompt, setStatus, searchFileChanges,
        ]
    }

    enum Rpir {

        static let next = GmAgentRpirNextTool()

        static let openBriefing = GmAgentRpirOpenBriefingTool()
        static let writeBrief = GmAgentRpirWriteBriefTool()
        static let closeBrief = GmAgentRpirCloseBriefTool()
        static let loadExplorationBrief = GmAgentRpirLoadBriefTool()

        static let openExploration = GmAgentRpirOpenExplorationTool()
        static let writeExplorations = GmAgentRpirWriteExplorationsTool()
        static let rankExplorations = GmAgentRpirRankExplorationsTool()
        static let completeExploration = GmAgentRpirCompleteExplorationTool()
        static let getExploration = GmAgentRpirGetExplorationTool()

        static let openClarification = GmAgentRpirOpenClarificationTool()
        static let writeClarificationQuestions =
            GmAgentRpirWriteClarificationQuestionsTool()
        static let writeClarificationNotes = GmAgentRpirWriteClarificationNotesTool()
        static let answerClarificationQuestion =
            GmAgentRpirAnswerClarificationQuestionTool()
        static let sealClarification = GmAgentRpirSealClarificationTool()
        static let finalizeClarification = GmAgentRpirFinalizeClarificationTool()
        static let openCarePackage = GmAgentRpirOpenCarePackageTool()
        static let writeCarePackage = GmAgentRpirWriteCarePackageTool()
        static let closeCarePackage = GmAgentRpirCloseCarePackageTool()
        static let getClarification = GmAgentRpirGetClarificationTool()
        static let getCarePackage = GmAgentRpirGetCarePackageTool()

        static let openArchitecture = GmAgentRpirOpenArchitectureTool()
        static let openArchitectureOption = GmAgentRpirOpenArchitectureOptionTool()
        static let writeArchitecturePersistenceChanges =
            GmAgentRpirWriteArchitecturePersistenceChangesTool()
        static let writeArchitectureFieldChanges =
            GmAgentRpirWriteArchitectureFieldChangesTool()
        static let writeArchitectureGeneralChanges =
            GmAgentRpirWriteArchitectureGeneralChangesTool()
        static let summarizeArchitecture = GmAgentRpirSummarizeArchitectureTool()
        static let proposeArchitecture = GmAgentRpirProposeArchitectureTool()
        static let approveArchitecture = GmAgentRpirApproveArchitectureTool()
        static let reviseArchitecture = GmAgentRpirReviseArchitectureTool()
        static let decideArchitecture = GmAgentRpirDecideArchitectureTool()
        static let getArchitecture = GmAgentRpirGetArchitectureTool()

        static let openReview = GmAgentRpirOpenReviewTool()
        static let writeReviews = GmAgentRpirWriteReviewsTool()
        static let rankReviews = GmAgentRpirRankReviewsTool()
        static let completeReview = GmAgentRpirCompleteReviewTool()
        static let resolveReviewFinding = GmAgentRpirResolveReviewFindingTool()
        static let getReview = GmAgentRpirGetReviewTool()

        static let searchExploration = GmAgentRpirSearchExplorationTool()
        static let searchClarification = GmAgentRpirSearchClarificationTool()
        static let searchArchitecture = GmAgentRpirSearchArchitectureTool()
        static let searchArchitectureOption = GmAgentRpirSearchArchitectureOptionTool()
        static let searchReview = GmAgentRpirSearchReviewTool()

        static let all: [any GmAgentTool] = [
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

    static let all: [any GmAgentTool] =
        Dope.all + Kbite.all + Diagram.all + Cde.all + Rpir.all + Projects.all
        + System.all + Fs.all

    static func tools(in family: GmAgentToolFamily) -> [any GmAgentTool] {
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
