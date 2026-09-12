import Foundation
import FoundationModels

// The navigable surface: `GmAgentTools.dope.searchSession`, and the flat roster
// behind it.
//
// WHY THIS IS A SEPARATE TYPE and not members on `GmAgentTool`. The shape asked
// for was `GmAgentTool.dope.<toolName>`, but `GmAgentTool` is a PROTOCOL —
// static members reaching concrete tool values cannot hang off it. So the
// namespace is its own caseless enum, and the family members are lowercase so
// the call site reads the way it was asked to read.
//
// WHAT THE ROSTER IS FOR, beyond convenience. `all` is what makes a drift test
// possible: a tool type that exists but is unreachable from the namespace fails
// `GmAgentToolRosterTests` rather than sitting in the module unnoticed. That is
// `VerbRegistryTests`' guarantee — "adding a verb without adding a row FAILS THE
// BUILD" — applied to this surface.
//
// IT AUTHORIZES NOTHING. This enumerates and classifies; it does not decide who
// may call what. That is deliberate and worth stating plainly, because a
// registry is exactly the place someone would later add a permission check: this
// is a single-user local harness, there is no caller to constrain, and the
// workflow's methodology (one reader calibrates, decides and seals) is guidance
// carried in doc comments and in each agent's own tool list — never a refusal
// from here.

/// The tool surface, navigable by family.
@available(GmAgentOs 1.0, *)
public enum GmAgentTools {

    /// Doped data — the repo's tree and the session overlays.
    public enum dope {
        public static let searchGlobal = GmAgentDopeSearchGlobalTool()
        public static let searchSession = GmAgentDopeSearchSessionTool()
        public static let updateSessionDope = GmAgentDopeUpdateSessionTool()

        public static let all: [any GmAgentTool] = [
            searchGlobal, searchSession, updateSessionDope,
        ]
    }

    /// Kbites and maws.
    public enum kbite {
        public static let search = GmAgentKbiteSearchTool()
        public static let openMaw = GmAgentKbiteOpenMawTool()
        public static let digest = GmAgentKbiteDigestTool()

        public static let all: [any GmAgentTool] = [search, openMaw, digest]
    }

    /// Diagrams. Placeholder family.
    public enum diagram {
        public static let notSupported = GmAgentDiagramPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    /// Projects, instances and sessions.
    public enum projects {
        public static let search = GmAgentProjectsSearchTool()
        public static let updateSession = GmAgentProjectsUpdateSessionTool()

        public static let all: [any GmAgentTool] = [search, updateSession]
    }

    /// Global configuration. Placeholder family.
    public enum system {
        public static let notSupported = GmAgentSystemPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    /// The gmfs root. Placeholder family.
    public enum fs {
        public static let notSupported = GmAgentFsPlaceholderTool()

        public static let all: [any GmAgentTool] = [notSupported]
    }

    /// The workflow machine — the family everything else supports.
    public enum cde {
        // Lifecycle
        public static let initialize = GmAgentCdeInitTool()
        public static let loadPrompt = GmAgentCdeLoadPromptTool()
        public static let setStatus = GmAgentCdeSetStatusTool()
        public static let next = GmAgentCdeNextTool()

        // Briefing
        public static let openBriefing = GmAgentCdeOpenBriefingTool()
        public static let writeBrief = GmAgentCdeWriteBriefTool()
        public static let closeBrief = GmAgentCdeCloseBriefTool()
        public static let loadExplorationBrief = GmAgentCdeLoadBriefTool()

        // Exploration
        public static let openExploration = GmAgentCdeOpenExplorationTool()
        public static let writeExplorations = GmAgentCdeWriteExplorationsTool()
        public static let rankExplorations = GmAgentCdeRankExplorationsTool()
        public static let completeExploration = GmAgentCdeCompleteExplorationTool()
        public static let getExploration = GmAgentCdeGetExplorationTool()

        // Clarification + care package
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

        // Architecture
        public static let openArchitectureOption = GmAgentCdeOpenArchitectureOptionTool()
        public static let writeArchitecturePersistenceChanges =
            GmAgentCdeWriteArchitecturePersistenceChangesTool()
        public static let writeArchitectureGeneralChanges =
            GmAgentCdeWriteArchitectureGeneralChangesTool()
        public static let decideArchitecture = GmAgentCdeDecideArchitectureTool()
        public static let getArchitecture = GmAgentCdeGetArchitectureTool()

        // Review — every entry below is DERIVED; see GmAgentCdeTool+Review.swift.
        public static let openReview = GmAgentCdeOpenReviewTool()
        public static let writeReviews = GmAgentCdeWriteReviewsTool()
        public static let rankReviews = GmAgentCdeRankReviewsTool()
        public static let completeReview = GmAgentCdeCompleteReviewTool()
        public static let resolveReviewFinding = GmAgentCdeResolveReviewFindingTool()
        public static let getReview = GmAgentCdeGetReviewTool()

        // Searches
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

    /// Every tool in the surface.
    ///
    /// An existential array so callers — and the roster test — can walk the
    /// whole surface without knowing the concrete types.
    public static let all: [any GmAgentTool] =
        dope.all + kbite.all + diagram.all + cde.all + projects.all + system.all + fs.all

    /// The tools in one family.
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
