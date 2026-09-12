import Foundation
import FoundationModels

public enum GmAgentToolFamily: String, Sendable, CaseIterable {
    ///
    case dope
    ///
    case kbite
    ///
    case diagram
    ///
    case cde
    ///
    case system
}

@available(GmAgentOs 1.0, *)
public protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }
}

@available(GmAgentOs 1.0, *)
public protocol GmDopeAgentTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmDopeAgentTool {
    public var family: GmAgentToolFamily { .dope }
}

@available(GmAgentOs 1.0, *)
public protocol GmKbiteAgentTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmKbiteAgentTool {
    public var family: GmAgentToolFamily { .kbite }
}

@available(GmAgentOs 1.0, *)
public protocol GmDiagramAgentTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmDiagramAgentTool {
    public var family: GmAgentToolFamily { .diagram }
}

@available(GmAgentOs 1.0, *)
public protocol GmCdeAgentTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmCdeAgentTool {
    public var family: GmAgentToolFamily { .cde }
}

@available(GmAgentOs 1.0, *)
public protocol GmSystemAgentTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmSystemAgentTool {
    public var family: GmAgentToolFamily { .system }
}
