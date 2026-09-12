import Foundation
import FoundationModels

// The agent-tool surface: seven families, one marker protocol each, and the
// root protocol they all refine.
//
// WHAT `Tool` ACTUALLY REQUIRES, read from the macOS 27 SDK rather than
// remembered, because three of its properties shape every type in this package:
//
//   - `description` is the ONLY member with no default implementation. `name`,
//     `parameters` and `includesSchemaInInstructions` are all defaulted. So the
//     one thing every conformance must author is the sentence the model reads
//     when deciding whether to call it. Those sentences are written plainly and
//     concretely here, as the prompt asked, because a vague description is the
//     one defect a compiler cannot catch.
//   - `Arguments` must conform to `Generable`, not merely
//     `ConvertibleFromGeneratedContent`, or the free `parameters` schema is
//     lost. The SDK makes this an error rather than a degrade: `Arguments ==
//     String` and `Arguments == Int` carry `@available(*, unavailable)`
//     overloads reading "use '@Generable' struct instead". Every tool therefore
//     declares its own @Generable argument struct; there are no scalar
//     shortcuts to reach for.
//   - `Output` may be a @Generable struct. Worth stating because it is not
//     visible from the `Tool` declaration: it holds through two refinements,
//     `Generable: ConvertibleToGeneratedContent` and
//     `ConvertibleToGeneratedContent: PromptRepresentable`. Structured results
//     are therefore free, and preferred — returning `String` also compiles and
//     throws the schema away.
//
// AVAILABILITY. `Tool`, `@Generable` and `@Guide` are all macOS 26; only the
// `@Generable(name:description:)` overload needs 27. `GmAgentOs 1.0` is defined
// as 27 in Package.swift, so the annotation on everything here is MORE
// conservative than the framework demands. Keep it that way and keep the
// package platform at macOS 26 — CI pins macos-26, and raising the floor to
// match the annotation would break the runner rather than tighten anything.
//
// NOTHING HERE IS WIRED. Every `call(arguments:)` in this package throws, and
// the throw names the daemon verb it will eventually send. The prompt behind
// this surface stages types and schemas so the cutover has something to connect
// to; making the calls real is separate work.

/// The seven families every tool belongs to. A tool's family is not metadata —
/// it is how the surface is navigated (see `GmAgentTools`), and it is what the
/// roster test checks a tool is filed under correctly.
public enum GmAgentToolFamily: String, Sendable, CaseIterable {
    /// controls tools related to doped data and managed gmfs or repo .doped data
    case dope
    /// managed kbites, maws, kbite search, etc
    case kbite
    /// Manages diagram searching, editing, parsing, and more
    case diagram
    /// This is the bread and butter domain area which covers all agentic
    /// machine loop behaviors needed to drive development in harnesses.
    case cde
    /// Controls the more general / shared parts of the system
    case projects
    /// Controls global configurations, behaviors
    case system
    /// Controls access to ~/gmfs directly for various functionality.
    case fs
}

/// The root of the surface. Refines FoundationModels' `Tool` and adds exactly
/// one requirement: which family the tool belongs to.
///
/// It stays this thin on purpose. Anything else added here would be added to
/// every tool in seven families at once, and the constrained-subset rule this
/// surface was built under cuts the other way.
@available(GmAgentOs 1.0, *)
public protocol GmAgentTool: Tool {
    var family: GmAgentToolFamily { get }
}

// The seven family markers. Each is an empty protocol plus an extension that
// pre-sets `family`, so a concrete tool declares its family by choosing which
// one to conform to and never writes the property itself.
//
// NAMING: GmAgent<Family>Tool, prefix and not infix. These were spelled
// GmDopeAgentTool / GmKbiteAgentTool / GmDiagramAgentTool / GmCdeAgentTool /
// GmSystemAgentTool until this pass. The renaming was free precisely because
// nothing imports this package yet, and it stops being free the moment
// something does.

/// Tools over doped data — the repo's `.gmcc/` tree and the session overlays.
@available(GmAgentOs 1.0, *)
public protocol GmAgentDopeTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentDopeTool {
    public var family: GmAgentToolFamily { .dope }
}

/// Tools over kbites and maws. Chewing is deliberately not here — it stays in
/// the plugin for now.
@available(GmAgentOs 1.0, *)
public protocol GmAgentKbiteTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentKbiteTool {
    public var family: GmAgentToolFamily { .kbite }
}

/// Diagram tools. A placeholder family — see `GmAgentUnsupportedTools`.
@available(GmAgentOs 1.0, *)
public protocol GmAgentDiagramTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentDiagramTool {
    public var family: GmAgentToolFamily { .diagram }
}

/// The workflow machine: briefing, exploration, clarification, architecture,
/// review. The family everything else supports.
@available(GmAgentOs 1.0, *)
public protocol GmAgentCdeTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentCdeTool {
    public var family: GmAgentToolFamily { .cde }
}

/// Projects, instances and sessions — the shared tier above a prompt.
@available(GmAgentOs 1.0, *)
public protocol GmAgentProjectsTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentProjectsTool {
    public var family: GmAgentToolFamily { .projects }
}

/// Global configuration and behaviour. A placeholder family.
@available(GmAgentOs 1.0, *)
public protocol GmAgentSystemTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentSystemTool {
    public var family: GmAgentToolFamily { .system }
}

/// Direct access to the `~/gmfs` filesystem root. A placeholder family.
///
/// When it is filled in, the write-containment invariant applies to it before
/// anything else: `Paths.assertContained(_:)` in gmDaemonSdk throws unless a
/// URL is under the filesystem root or the working repo, and a tool family
/// whose whole purpose is filesystem access is the one most able to get that
/// wrong.
@available(GmAgentOs 1.0, *)
public protocol GmAgentFsTool: GmAgentTool {}

@available(GmAgentOs 1.0, *)
extension GmAgentFsTool {
    public var family: GmAgentToolFamily { .fs }
}
