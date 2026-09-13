import Foundation
import FoundationModels

public enum GmAgentToolFamily: String, Sendable, CaseIterable {

    case dope

    case kbite

    case diagram

    case cde

    case projects

    case system

    case fs
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentDopeTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentDopeTool {
    public var family: GmAgentToolFamily { .dope }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentKbiteTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentKbiteTool {
    public var family: GmAgentToolFamily { .kbite }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentDiagramTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentDiagramTool {
    public var family: GmAgentToolFamily { .diagram }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentCdeTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentCdeTool {
    public var family: GmAgentToolFamily { .cde }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentProjectsTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentProjectsTool {
    public var family: GmAgentToolFamily { .projects }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentSystemTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentSystemTool {
    public var family: GmAgentToolFamily { .system }
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentFsTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentFsTool {
    public var family: GmAgentToolFamily { .fs }
}
