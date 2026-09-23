// The tools declared as deliberately unsupported, each naming why.

import Foundation
import FoundationModels

@Generable
struct GmAgentNoArguments: Sendable {
    /// Creates an empty arguments structure for unsupported tools.
    init() {}
}

struct GmAgentDiagramPlaceholderTool: GmAgentDiagramTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "diagram_not_supported"
    let description = notBuiltDescription("Look at and change pictures")

    /// Creates a placeholder tool that diagram operations are not supported.
    init() {}

    /// Throws an error indicating diagram tools are not implemented.
    ///
    /// - Returns: Never returns; always throws.
    /// - Throws: `GmAgentToolError.notImplemented(family: .diagram)`.
    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .diagram)
    }
}

struct GmAgentSystemPlaceholderTool: GmAgentSystemTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "system_not_supported"
    let description = notBuiltDescription("Change how the whole system behaves")

    /// Creates a placeholder tool that system operations are not supported.
    init() {}

    /// Throws an error indicating system tools are not implemented.
    ///
    /// - Returns: Never returns; always throws.
    /// - Throws: `GmAgentToolError.notImplemented(family: .system)`.
    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .system)
    }
}

struct GmAgentFsPlaceholderTool: GmAgentFsTool {
    static let ops: [GmAgentToolOp] = []
    static let refuses = true

    let name = "fs_not_supported"
    let description = notBuiltDescription("Touch files in the gmfs folder")

    /// Creates a placeholder tool that filesystem operations are not supported.
    init() {}

    /// Throws an error indicating filesystem tools are not implemented.
    ///
    /// - Returns: Never returns; always throws.
    /// - Throws: `GmAgentToolError.notImplemented(family: .fs)`.
    func call(arguments _: GmAgentNoArguments) throws -> String {
        throw GmAgentToolError.notImplemented(family: .fs)
    }
}
