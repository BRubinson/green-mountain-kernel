// The GmAgentTool protocol family and the tool-family vocabulary every tool declares itself under.

import Foundation
import FoundationModels

public enum GmAgentToolFamily: String, Sendable, CaseIterable {

    case dope

    case kbite

    case diagram

    case cde

    case rpir

    case projects

    case system

    case fs
}

public protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }
}

public protocol GmAgentDopeTool: GmAgentTool {}

extension GmAgentDopeTool {
    public var family: GmAgentToolFamily { .dope }
}

public protocol GmAgentKbiteTool: GmAgentTool {}

extension GmAgentKbiteTool {
    public var family: GmAgentToolFamily { .kbite }
}

public protocol GmAgentDiagramTool: GmAgentTool {}

extension GmAgentDiagramTool {
    public var family: GmAgentToolFamily { .diagram }
}

public protocol GmAgentCdeTool: GmAgentTool {}

extension GmAgentCdeTool {
    public var family: GmAgentToolFamily { .cde }
}

public protocol GmAgentRpirTool: GmAgentTool {}

extension GmAgentRpirTool {
    public var family: GmAgentToolFamily { .rpir }
}

public protocol GmAgentProjectsTool: GmAgentTool {}

extension GmAgentProjectsTool {
    public var family: GmAgentToolFamily { .projects }
}

public protocol GmAgentSystemTool: GmAgentTool {}

extension GmAgentSystemTool {
    public var family: GmAgentToolFamily { .system }
}

public protocol GmAgentFsTool: GmAgentTool {}

extension GmAgentFsTool {
    public var family: GmAgentToolFamily { .fs }
}
