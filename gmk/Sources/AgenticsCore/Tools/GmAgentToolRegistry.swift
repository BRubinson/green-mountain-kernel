// The namespace that makes every GmAgentTool conformance reachable in one place.

import Foundation
import FoundationModels

enum GmAgentTools {

    static let cdeInit = GmAgentCdeInitTool()

    static let cdePrompt = GmAgentCdePromptTool()

    static let cdeSession = GmAgentCdeSessionTool()

    static let cdeRpirBriefing = GmAgentCdeRpirBriefingTool()

    static let cdeRpirExplore = GmAgentCdeRpirExploreTool()

    static let cdeRpirClarify = GmAgentCdeRpirClarifyTool()

    static let cdeRpirArchitecture = GmAgentCdeRpirArchitectureTool()

    static let cdeRpirReview = GmAgentCdeRpirReviewTool()

    static let cdeRpirSearch = GmAgentCdeRpirSearchTool()

    static let cdeDope = GmAgentCdeDopeTool()

    static let cdeKbite = GmAgentCdeKbiteTool()

    static let diagramNotSupported = GmAgentDiagramPlaceholderTool()

    static let systemNotSupported = GmAgentSystemPlaceholderTool()

    static let fsNotSupported = GmAgentFsPlaceholderTool()

    enum Dope {
        static let all: [any GmAgentTool] = [GmAgentTools.cdeDope]
    }

    enum Kbite {
        static let all: [any GmAgentTool] = [GmAgentTools.cdeKbite]
    }

    enum Diagram {
        static let all: [any GmAgentTool] = [GmAgentTools.diagramNotSupported]
    }

    enum Projects {
        static let all: [any GmAgentTool] = [GmAgentTools.cdeSession]
    }

    enum System {
        static let all: [any GmAgentTool] = [GmAgentTools.systemNotSupported]
    }

    enum Fs {
        static let all: [any GmAgentTool] = [GmAgentTools.fsNotSupported]
    }

    enum Cde {
        static let all: [any GmAgentTool] = [GmAgentTools.cdeInit, GmAgentTools.cdePrompt]
    }

    enum Rpir {
        static let all: [any GmAgentTool] = [
            GmAgentTools.cdeRpirBriefing,
            GmAgentTools.cdeRpirExplore,
            GmAgentTools.cdeRpirClarify,
            GmAgentTools.cdeRpirArchitecture,
            GmAgentTools.cdeRpirReview,
            GmAgentTools.cdeRpirSearch,
        ]
    }

    static let all: [any GmAgentTool] =
        Dope.all + Kbite.all + Diagram.all + Cde.all + Rpir.all + Projects.all
        + System.all + Fs.all

    /// The served roster as names, in declaration order — what the generator
    /// checks the emitted roster against.
    static var names: [String] {
        all.map(\.name)
    }

    /// Returns all tools in the given family.
    /// - Parameter family: The tool family to retrieve.
    /// - Returns: An array of tools belonging to the family.
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
