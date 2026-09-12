import Foundation
import FoundationModels

// The three placeholder families: diagram, system, fs.
//
// WHY THESE EXIST AS TOOLS AT ALL, rather than as empty marker protocols with no
// conformances. A model-facing surface fails in two different ways, and they are
// not equally recoverable:
//
//   - A tool that is ABSENT teaches the model the capability does not exist
//     here. It goes looking for another route — a shell command, a neighbouring
//     verb, a guess — and once it is off the surface for one thing it tends to
//     stay off it.
//   - A tool that is PRESENT and refuses teaches the model the capability is
//     planned and not yet reachable. It reports that and moves on.
//
// The second is the better failure, and it costs one type each. It also makes
// the roster test meaningful: every family has at least one tool, so a family
// added to the enum and then forgotten fails the build instead of quietly
// existing as a name nobody implemented.
//
// WHAT THEY MUST NEVER DO is return an empty success. An unimplemented tool that
// answers `[]` is indistinguishable from a real empty result and will be
// believed — which is how a model concludes there are no diagrams rather than
// that it cannot see them.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentNoArguments: Sendable {
    public init() {}
}

/// Look at and change pictures. NOT BUILT YET.
///
/// The family will cover diagram searching, editing, parsing and more. The
/// daemon already serves a substantial diagram surface — init, list, get, the
/// node verbs, batch apply, search, delete, and the repo write/ingest pair — so
/// filling this in is a matter of choosing the constrained subset, not of
/// building anything underneath.
@available(GmAgentOs 1.0, *)
public struct GmAgentDiagramPlaceholderTool: GmAgentDiagramTool {
    public let name = "diagram_not_supported"
    public let description = "Look at and change pictures. NOT BUILT YET."

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .diagram)
    }
}

/// Change how the whole system behaves. NOT BUILT YET.
///
/// Global configuration and behaviour. `CONFIG_SET` is the obvious verb behind
/// it, and it is exactly the sort of thing to be deliberate about exposing:
/// config keys are enum-bound precisely so that config stays a typed subsystem
/// rather than a free-form bag, and an agent-facing writer into it deserves more
/// thought than a mechanical wrapper.
@available(GmAgentOs 1.0, *)
public struct GmAgentSystemPlaceholderTool: GmAgentSystemTool {
    public let name = "system_not_supported"
    public let description = "Change how the whole system behaves. NOT BUILT YET."

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .system)
    }
}

/// Touch files in the gmfs folder. NOT BUILT YET.
///
/// Direct access to the `~/gmfs` root.
///
/// WHEN THIS IS FILLED IN, containment comes first. The rule is that nothing
/// writes outside the filesystem root or the working repo, and it is ENFORCED
/// rather than documented: `Paths.assertContained(_:)` throws, and every
/// kit-side write routes through it. A tool family whose entire purpose is
/// filesystem access is the one most able to route around that by accident, so
/// whatever lands here goes through the same door as everything else.
@available(GmAgentOs 1.0, *)
public struct GmAgentFsPlaceholderTool: GmAgentFsTool {
    public let name = "fs_not_supported"
    public let description = "Touch files in the gmfs folder. NOT BUILT YET."

    public init() {}

    public func call(arguments: GmAgentNoArguments) async throws -> String {
        throw GmAgentToolError.notImplemented(family: .fs)
    }
}
