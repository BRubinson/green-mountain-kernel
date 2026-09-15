
import ClaudeForFoundationModels
import Foundation
import GmDaemonSdk

public enum GmAgentModelChoice: String, Sendable, Hashable, Codable, CaseIterable {

    case haiku

    case sonnetMid = "sonnet_mid"

    case sonnetHigh = "sonnet_high"

    case opusLow = "opus_low"

    case opusMid = "opus_mid"

    case opusHigh = "opus_high"

    case opusXhigh = "opus_xhigh"

    case opusMax = "opus_max"

    public var model: ClaudeModel {
        switch self {
        case .haiku: return .haiku4_5
        case .sonnetMid, .sonnetHigh: return .sonnet5
        case .opusLow, .opusMid, .opusHigh, .opusXhigh, .opusMax: return .opus5
        }
    }

    public var requestedEffort: ClaudeModel.Effort? {
        switch self {
        case .haiku: return nil
        case .sonnetMid, .opusMid: return .medium
        case .sonnetHigh, .opusHigh: return .high
        case .opusLow: return .low
        case .opusXhigh: return .xhigh
        case .opusMax: return .max
        }
    }

    public var effort: ClaudeModel.Effort? {
        Self.clamp(requestedEffort, to: model)
    }

    public var fallbacks: ClaudeFallbacks {
        switch self {
        case .opusLow, .opusMid, .opusHigh, .opusXhigh, .opusMax: return .serverDefault
        case .haiku, .sonnetMid, .sonnetHigh: return []
        }
    }

    public var summary: String {
        let effortText = effort.map { " @ \($0.rawValue)" } ?? " (no effort control)"
        return "\(model.id)\(effortText)"
    }

    private static func rank(_ effort: ClaudeModel.Effort) -> Int {
        switch effort {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .xhigh: return 3
        case .max: return 4
        }
    }

    private static func clamp(
        _ requested: ClaudeModel.Effort?,
        to model: ClaudeModel
    ) -> ClaudeModel.Effort? {
        guard let requested else { return nil }
        let accepted = model.capabilities.effortLevels
        if accepted.contains(requested) { return requested }
        return
            accepted
            .filter { rank($0) <= rank(requested) }
            .max { rank($0) < rank($1) }
    }
}

extension GmAgentModelChoice {

    public func languageModel(
        auth: AuthMode,
        serverTools: Set<ClaudeServerTool> = [],
        timeout: TimeInterval = 600
    ) -> ClaudeLanguageModel {
        ClaudeLanguageModel(
            name: model,
            auth: auth,
            fixedEffort: effort,
            fallbacks: fallbacks,
            serverTools: serverTools,
            timeout: timeout
        )
    }
}

public enum GmAgentModelChoiceConfig {

    public static func choice(
        for phase: WorkflowSpec.Phase,
        methodology: ExplorationAgentType? = nil
    ) -> GmAgentModelChoice {
        _ = methodology
        switch phase {
        case .briefing: return .haiku
        case .explore: return .opusMid
        case .clarifyOpen: return .opusHigh
        case .clarifyUser: return .opusHigh
        case .carePackage: return .opusHigh
        case .archOptions: return .opusHigh
        case .architecture: return .opusXhigh
        case .planGate: return .opusHigh
        case .implement: return .opusXhigh
        case .review: return .opusHigh
        case .reviewFix: return .opusHigh
        case .done: return .sonnetMid
        }
    }

    public static func choice(for role: GmAgentRole) -> GmAgentModelChoice {
        switch role {
        case .primary: return .opusHigh
        case .doper: return .haiku
        case .explorer: return .opusMid
        case .clarifier: return .opusHigh
        case .architect: return .opusHigh
        case .reviewer: return .opusHigh
        case .kbiteChewer: return .haiku
        case .mawFetcher: return .haiku
        }
    }

    public static func table(for variant: BotVariant) -> [(WorkflowSpec.Phase, GmAgentModelChoice)] {
        WorkflowSpec.phases(for: variant).map { ($0, choice(for: $0)) }
    }
}

extension WorkflowSpec.Phase {

    public var modelChoice: GmAgentModelChoice {
        GmAgentModelChoiceConfig.choice(for: self)
    }
}
