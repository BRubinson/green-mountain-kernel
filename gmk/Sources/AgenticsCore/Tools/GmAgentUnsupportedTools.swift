// The tools declared as deliberately unsupported, each naming why.

import Foundation
import FoundationModels

@Generable
struct GmAgentNoArguments: Sendable {
    init() {}
}

struct GmAgentDiagramPlaceholderTool: GmAgentDiagramTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "diagram_not_supported"
    let description = notBuiltDescription("Look at and change pictures")

    init() {}

    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .diagram)
    }
}

struct GmAgentSystemPlaceholderTool: GmAgentSystemTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "system_not_supported"
    let description = notBuiltDescription("Change how the whole system behaves")

    init() {}

    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .system)
    }
}

struct GmAgentFsPlaceholderTool: GmAgentFsTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "fs_not_supported"
    let description = notBuiltDescription("Touch files in the gmfs folder")

    init() {}

    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .fs)
    }
}
