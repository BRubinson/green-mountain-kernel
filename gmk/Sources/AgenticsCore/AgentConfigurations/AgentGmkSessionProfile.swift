// Every session identity the kit can wear, each resolving to one precompiled instruction.

import Foundation

/// The twelve session profiles: four workflow missions and eight bespoke
/// directives.
///
/// A mission profile is what a COMMAND embodies — mission text plus the whole
/// phase walk. A directive profile is what an AGENT embodies — one role and its
/// steps. `team` carries the primarch's directive alone: a team flow spawns a
/// subagent per lens already wearing its own, so handing the primary all eight
/// would duplicate that text into the primary's context.
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
            uniqueKeysWithValues: allCases.map { ($0, AgentGmkInstruction($0.compile())) }
        )

    /// Assembly order is longest-lived content first: core, then personality,
    /// then the directive text, then the mission and its phase walk. A profile
    /// never reorders these, so the prefix every profile shares stays a shared
    /// prefix.
    private func compile() -> String {
        var parts = [GM_AGENT_CORE, AgentGmkPersonality.compliant.text, directiveText]
        if let mission {
            parts.append(mission.text)
            if let phaseIndex = mission.phaseIndex { parts.append(phaseIndex) }
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
