// Every session identity the kit can wear, each resolving to one precompiled instruction.

import Foundation

/// The twelve session profiles: four workflow missions and eight bespoke
/// directives.
///
/// The two halves answer different questions and are deliberately one type:
///
/// - **Mission profiles** (`task`/`bot`/`rpi`/`team`) are what a COMMAND
///   embodies. They carry the mission text and the full phase walk, so the
///   instruction describes the whole workflow rather than one step of it.
/// - **Directive profiles** are what an AGENT embodies — one role, its own
///   steps, and nothing else.
///
/// `team` is the one mission that does NOT wear every directive. It carries the
/// primarch's alone, because a team flow spawns a subagent per lens and each of
/// those already arrives wearing its own directive profile. Handing the primary
/// all eight would duplicate into the primary's context exactly the text its
/// subagents were spawned to hold.
enum AgentGmkSessionProfile: String, Sendable, Hashable, Codable, CaseIterable {

    case task
    case bot
    case rpi
    case team

    case primarch
    case briefer
    case explorer
    case intentClarifier
    case architect
    case implementor
    case reviewer
    case kbiteChewer

    /// The mission this profile drives, or `nil` for a directive profile.
    var mission: AgentGmkMission? {
        switch self {
        case .task: return .task
        case .bot: return .bot
        case .rpi: return .rpi
        case .team: return .team
        case .primarch, .briefer, .explorer, .intentClarifier, .architect,
            .implementor, .reviewer, .kbiteChewer:
            return nil
        }
    }

    /// The role this profile wears. A mission profile wears the primarch's — the
    /// primary is who runs a workflow.
    var directive: AgentGmkDirective {
        switch self {
        case .task, .bot, .rpi, .team, .primarch: return .primarch
        case .briefer: return .briefer
        case .explorer: return .explorer
        case .intentClarifier: return .intentClarifier
        case .architect: return .architect
        case .implementor: return .implementor
        case .reviewer: return .reviewer
        case .kbiteChewer: return .kbiteChewer
        }
    }

    /// The compiled body. Assembled once per process, not per call — see
    /// ``AgentGmkInstruction`` for why that matters.
    var instruction: AgentGmkInstruction {
        Self.compiled[self] ?? AgentGmkInstruction(compile())
    }

    private static let compiled: [AgentGmkSessionProfile: AgentGmkInstruction] =
        Dictionary(
            uniqueKeysWithValues: allCases.map { ($0, AgentGmkInstruction($0.compile())) })

    /// Assembly order is longest-lived content first: core, then personality,
    /// then the directive text, then the mission and its phase walk. A profile
    /// never reorders these, so the prefix every profile shares stays a shared
    /// prefix.
    private func compile() -> String {
        var parts = [GM_AGENT_CORE, AgentGmkPersonality.compliant.text, directiveText]
        if let mission {
            parts.append(mission.text)
            parts.append(contentsOf: mission.phases.map(mission.template(for:)))
        } else {
            parts.append(directive.steps)
        }
        return parts.joined(separator: "\n\n")
    }

    /// A mission that wears every directive gets all eight; `team` and every
    /// directive profile get exactly one.
    private var directiveText: String {
        guard let mission, mission.wearsEveryDirective else { return directive.text }
        return AgentGmkDirective.allCases.map(\.text).joined(separator: "\n\n")
    }
}
