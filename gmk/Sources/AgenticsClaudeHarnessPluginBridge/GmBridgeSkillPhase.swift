// The twelve per-phase workflow skills: one SKILL.md per RPIR phase.

import Foundation
import FoundationModels

/// The phase skills, emitted at `skills/cde_rpir_<phase>/SKILL.md`.
///
/// Each carries one phase's Calls and Gate and nothing else, so a run loads the
/// phase it is in rather than the whole walk. The mission's phase index says
/// when to load one, and the model may also reach for one itself — a skill that
/// is neither user-invocable nor model-invocable has no invoker at all.
enum GmBridgeSkillPhase {

    static let all: [GmBridgeSkill.File] =
        GmCdeRpirWorkflowPhase.allCases.map(GmBridgeSkill.File.init(phase:))

    /// The phase skills as markdown bullets, for a skill body that points at them.
    static var index: String {
        all
            .map { "- `gmcc:\($0.name)` — \($0.description ?? "")" }
            .joined(separator: "\n")
    }
}

extension GmCdeRpirWorkflowPhase {

    /// The skill a phase's instructions live in.
    var skillName: String { "cde_rpir_\(rawValue)" }

    /// One clause, because it sits in every session's skill listing.
    var skillBrief: String {
        switch self {
        case .briefing:
            return "The BRIEFING phase: the prompt's opinion-free orientation page, sealed before anything else moves."
        case .explore:
            return "The EXPLORE phase: one finding list per explorer, written as the codebase is read."
        case .clarifyOpen:
            return "The CLARIFY_OPEN phase: rank the whole record, seal the synthesis, author the question suite."
        case .clarifyUser:
            return "The CLARIFY_USER phase: the one conversation with the Endotherm, and its recorded answers."
        case .carePackage:
            return "The CARE_PACKAGE phase: the clarified intent curated into the package architecture reads."
        case .archOptions:
            return "The ARCH_OPTIONS phase: rival plans written in parallel, one per lens."
        case .architecture:
            return "The ARCHITECTURE phase: the plan, persistence changes first and general changes built over them."
        case .planGate:
            return "The PLAN_GATE phase: the Endotherm approves the plan before a stone is cut."
        case .implement:
            return "The IMPLEMENT phase: the approved change landed, only in the files the plan names."
        case .review:
            return "The REVIEW phase: what was built judged against what was asked."
        case .reviewFix:
            return "The REVIEW_FIX phase: the settled findings resolved and the rest ruled on."
        case .done:
            return "The DONE phase: the prompt closed and the activation claim released."
        }
    }

    /// The cde tools this phase's calls reach for, read off the rendered body
    /// rather than listed a second time here; every phase also gets `cde_init`.
    var skillTools: [any GmAgentTool] {
        let cited = GmBridgeWriter.citedToolNames(in: template)
        let entry = GmAgentTools.cdeInit.name
        return [GmAgentTools.cdeInit]
            + GmAgentTools.all.filter { cited.contains($0.name) && $0.name != entry }
    }
}

extension GmBridgeSkill.File {

    init(phase: GmCdeRpirWorkflowPhase) {
        self.init(
            name: phase.skillName,
            description: phase.skillBrief,
            userInvocable: false,
            allowedTools: phase.skillTools.map { GmBridgeSkill.Tool.mcp(GmBridgeMcpTool($0)) },
            model: .opus,
            body: phase.template
        )
    }
}
