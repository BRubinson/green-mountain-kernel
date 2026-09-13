// The tools declared as deliberately unsupported, each naming why.

import Foundation
import FoundationModels

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentNoArguments: Sendable {
    public init() {}
}

@available(GmAgentOs 1.0, *)
public struct GmAgentDiagramPlaceholderTool: GmAgentDiagramTool {
    public let name = "diagram_not_supported"
    public let description = notBuiltDescription("Look at and change pictures")

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .diagram)
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentSystemPlaceholderTool: GmAgentSystemTool {
    public let name = "system_not_supported"
    public let description = notBuiltDescription("Change how the whole system behaves")

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .system)
    }
}

@available(GmAgentOs 1.0, *)
public struct GmAgentFsPlaceholderTool: GmAgentFsTool {
    public let name = "fs_not_supported"
    public let description = notBuiltDescription("Touch files in the gmfs folder")

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .fs)
    }
}
