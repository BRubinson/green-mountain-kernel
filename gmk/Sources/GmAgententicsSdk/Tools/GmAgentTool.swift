// The GmAgentTool protocol family and the tool-family vocabulary every tool declares itself under.

import Foundation
import FoundationModels

enum GmAgentToolFamily: String, Sendable, CaseIterable {

    case dope

    case kbite

    case diagram

    case cde

    case rpir

    case projects

    case system

    case fs
}

protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }
}

protocol GmAgentDopeTool: GmAgentTool {}

extension GmAgentDopeTool {
    var family: GmAgentToolFamily { .dope }
}

protocol GmAgentKbiteTool: GmAgentTool {}

extension GmAgentKbiteTool {
    var family: GmAgentToolFamily { .kbite }
}

protocol GmAgentDiagramTool: GmAgentTool {}

extension GmAgentDiagramTool {
    var family: GmAgentToolFamily { .diagram }
}

protocol GmAgentCdeTool: GmAgentTool {}

extension GmAgentCdeTool {
    var family: GmAgentToolFamily { .cde }
}

protocol GmAgentRpirTool: GmAgentTool {}

extension GmAgentRpirTool {
    var family: GmAgentToolFamily { .rpir }
}

protocol GmAgentProjectsTool: GmAgentTool {}

extension GmAgentProjectsTool {
    var family: GmAgentToolFamily { .projects }
}

protocol GmAgentSystemTool: GmAgentTool {}

extension GmAgentSystemTool {
    var family: GmAgentToolFamily { .system }
}

protocol GmAgentFsTool: GmAgentTool {}

extension GmAgentFsTool {
    var family: GmAgentToolFamily { .fs }
}
