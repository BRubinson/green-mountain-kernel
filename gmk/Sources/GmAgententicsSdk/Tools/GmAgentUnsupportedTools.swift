// The tools declared as deliberately unsupported, each naming why.

import Foundation
import FoundationModels

@Generable
public struct GmAgentNoArguments: Sendable {
    public init() {}
}

public struct GmAgentDiagramPlaceholderTool: GmAgentDiagramTool {
    public let name = "diagram_not_supported"
    public let description = notBuiltDescription("Look at and change pictures")

    public init() {}

    public func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .diagram)
    }
}

public struct GmAgentSystemPlaceholderTool: GmAgentSystemTool {
    public let name = "system_not_supported"
    public let description = notBuiltDescription("Change how the whole system behaves")

    public init() {}

    public func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .system)
    }
}

public struct GmAgentFsPlaceholderTool: GmAgentFsTool {
    public let name = "fs_not_supported"
    public let description = notBuiltDescription("Touch files in the gmfs folder")

    public init() {}

    public func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .fs)
    }
}
