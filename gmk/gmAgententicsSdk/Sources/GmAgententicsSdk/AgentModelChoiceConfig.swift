//
//  AgentModelChoiceConfig.swift
//  gmAgententicsSdk
//
//  Created by Bryce Rubinson on 9/13/26.
//
//  Here we want to just make a enum pre-configured with our model configurations.
//
//  FIRST PASS — the assignments below are a starting position to argue with, not
//  a settled contract. What is NOT provisional is the shape: the preset is a
//  (model, effort) PAIR, the effort is CLAMPED to what the model accepts before
//  it is ever sent, and the routing table is keyed on the workflow PHASE rather
//  than on the persona. See the three notes on that choice below.
//
//  THIS FILE SENDS NOTHING. Like the rest of the package it is declaration only:
//  `languageModel(auth:)` constructs a value, and constructing a
//  `ClaudeLanguageModel` performs no I/O. Models stay daemon-managed — the same
//  reason `GmccAgenticPromptExecutionProfile` deliberately sets no `.model()`.

import ClaudeForFoundationModels
import Foundation
import GmDaemonSdk

// MARK: - The presets

/// One pre-configured Claude setup: a model, and how hard it is told to think.
///
/// THE TIER IS THE UNIT, NOT THE MODEL. A bare model id is not a configuration —
/// `claude-opus-5` at `.low` and `claude-opus-5` at `.max` differ by more in cost
/// and behaviour than Opus differs from Sonnet at a fixed effort. Every case here
/// therefore names both halves, and the case name says what you get.
///
/// Named by MECHANISM (`opusHigh`) rather than by JOB (`architectModel`) on
/// purpose: the job→tier mapping is the thing we expect to churn, and it lives in
/// ``GmAgentModelChoiceConfig`` where one edit moves a phase between tiers. If
/// the cases were named for jobs, re-pointing a job would mean either renaming a
/// case or leaving a name that lies.
public enum GmAgentModelChoice: String, Sendable, Hashable, Codable, CaseIterable {

    /// Haiku 4.5. Cheap, fast, no extended thinking, **no effort levels at all**.
    case haiku

    /// Sonnet 5 at medium effort.
    case sonnetMid = "sonnet_mid"

    /// Sonnet 5 at high effort.
    case sonnetHigh = "sonnet_high"

    /// Opus 5 at low effort — the subagent / mechanical-pass setting.
    case opusLow = "opus_low"

    /// Opus 5 at medium effort.
    case opusMid = "opus_mid"

    /// Opus 5 at high effort. The API's own default, and the general-purpose
    /// setting for intelligence-sensitive work.
    case opusHigh = "opus_high"

    /// Opus 5 at xhigh — the level between `high` and `max`, and the one tuned
    /// for coding and agentic loops.
    case opusXhigh = "opus_xhigh"

    /// Opus 5 at max. Correctness over cost.
    case opusMax = "opus_max"

    /// The model this preset selects.
    ///
    /// Every constant comes from the VENDORED ``ClaudeModel``, which carries the
    /// capability matrix alongside the id. That coupling is the point: a bare id
    /// string here would have to be paired with a hand-maintained guess at which
    /// request fields the model accepts, and a wrong guess is either a hard 400
    /// or a silently degraded request. Re-syncing the vendored package is what
    /// updates this table; do not write ids by hand.
    public var model: ClaudeModel {
        switch self {
        case .haiku: return .haiku4_5
        case .sonnetMid, .sonnetHigh: return .sonnet5
        case .opusLow, .opusMid, .opusHigh, .opusXhigh, .opusMax: return .opus5
        }
    }

    /// The effort this tier's NAME promises — before any capability check.
    ///
    /// Read ``effort`` instead when you are about to send a request. This one is
    /// kept public so the difference between what a tier asked for and what its
    /// model will accept is inspectable rather than swallowed.
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

    /// The effort that is actually safe to send: ``requestedEffort`` clamped down
    /// to the highest level ``model`` accepts, or `nil` when it accepts none.
    ///
    /// **THIS CLAMP IS LOAD-BEARING, NOT DEFENSIVE TIDINESS.**
    /// `ClaudeLanguageModel.init` asserts `fixedEffort` against
    /// `capabilities.effortLevels` with a `precondition` — a TRAP, not a thrown
    /// error, so a mismatch is a crash at construction and no `catch` reaches it.
    /// Haiku 4.5's effort set is EMPTY today, so `.haiku` with any effort at all
    /// would take the process down. Clamping here means no caller can assemble
    /// that call, which is the same reasoning that makes `KernelOwnership.Token`
    /// a type rather than a convention.
    ///
    /// It downgrades rather than nil-ing out an unsupported level, because the
    /// current mismatch (empty set) is not the only one that can appear: a model
    /// added later with a narrower ladder should quietly get its closest level
    /// instead of silently losing effort control entirely.
    public var effort: ClaudeModel.Effort? {
        Self.clamp(requestedEffort, to: model)
    }

    /// Refusal fallbacks to send with this tier.
    ///
    /// `.serverDefault` lets the API pick the substitute recommended for the
    /// policy area of a refusal, so we never maintain a model list. It is set on
    /// the **Opus tiers only**, deliberately: the API REJECTS `fallbacks` for a
    /// model that does not support them, and Opus 5 is the model we have
    /// documentation for. Widening this to Sonnet or Haiku is a one-line change
    /// that must be backed by a checked fact, not by symmetry.
    public var fallbacks: ClaudeFallbacks {
        switch self {
        case .opusLow, .opusMid, .opusHigh, .opusXhigh, .opusMax: return .serverDefault
        case .haiku, .sonnetMid, .sonnetHigh: return []
        }
    }

    /// One line, for logs and for the run bar. Not a doc comment — this is meant
    /// to be printed.
    public var summary: String {
        let effortText = effort.map { " @ \($0.rawValue)" } ?? " (no effort control)"
        return "\(model.id)\(effortText)"
    }

    // MARK: Clamping

    /// `low < medium < high < xhigh < max`. `ClaudeModel.Effort` is not
    /// `Comparable` upstream and it is VENDORED, so the order is restated here
    /// rather than added there — a local `Comparable` conformance would be a
    /// local modification to a package whose only sanctioned local modification
    /// is a provenance header.
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
        // Highest accepted level at or below what was asked for; if the model
        // accepts nothing that low (or nothing at all), send no effort field.
        return
            accepted
            .filter { rank($0) <= rank(requested) }
            .max { rank($0) < rank($1) }
    }
}

// MARK: - Building the model

extension GmAgentModelChoice {

    /// Build the `LanguageModel` this preset describes.
    ///
    /// **`fixedEffort` OUTRANKS THE FRAMEWORK'S REASONING HINT**, and that is the
    /// one interaction to hold in mind while reading this file next to
    /// `Templates/GmAgentInstruction.swift`. That profile sets
    /// `.reasoningLevel(.deep)` on divergent and convergent phases; once a tier
    /// here carries an effort, the effort wins and the reasoning level stops
    /// mattering. The two are not additive and they are not in conflict — one
    /// simply supersedes the other, and `nil` effort (`.haiku`) is the only case
    /// where the profile's hint survives. Decide which knob owns a phase; do not
    /// tune both and expect them to compose.
    ///
    /// - Parameters:
    ///   - auth: Credential mode. Nothing in this package holds a credential —
    ///     the caller supplies it, and a shipped app should be `.proxied` or
    ///     `.appAttest` rather than a bundled key.
    ///   - serverTools: Anthropic-hosted tools. Empty by default and that is the
    ///     GMK-correct default: our tool surface is the CDE tool families, which
    ///     the framework invokes client-side.
    ///   - timeout: Ten minutes, an order of magnitude over the vendored default
    ///     of 60s. A single high-effort turn on a real prompt runs for minutes,
    ///     and a timeout shorter than the work is a failure we manufactured.
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

// MARK: - The routing table

/// Which preset drives which piece of the workflow.
///
/// **KEYED ON PHASE, NOT ON PERSONA — the axis choice, stated once.** The phase
/// is what the daemon derives at every `BOT_NEXT`, so it is the thing actually
/// known at spawn time; the role is a pure function of it
/// (`GmAgentRole(driving:)`), which makes role-keying a second spelling of the
/// same table rather than a second axis. The role overload below exists for
/// callers holding a role with no phase in hand, and the two are kept
/// consistent by hand today.
///
/// **METHODOLOGY IS A DELIBERATE NON-AXIS, for now.** The parameter is on the
/// signature so the refinement point is visible in the type rather than buried
/// in a comment, and it currently changes nothing: the four exploration lenses
/// are meant to disagree about the CODE, and giving `aggressive` a stronger
/// model than `conservative` would make one lens win on horsepower instead of on
/// argument — which is the one thing a four-lens panel exists to prevent. If
/// this ever grows teeth, the likeliest first use is the opposite of the obvious
/// one: running a CHEAPER tier on a redundant lens, not a dearer one on a
/// favoured lens.
public enum GmAgentModelChoiceConfig {

    /// The preset for a workflow phase.
    ///
    /// The assignments, and the reasoning that is actually contestable:
    ///
    /// - `.briefing` is **Haiku**. The doper's contract is explicitly
    ///   OPINION-FREE — it searches dope and kbites and writes a ref set. That
    ///   is retrieval, not judgement, and it is the one phase whose output
    ///   quality is measured by coverage rather than by insight.
    /// - `.explore` is **Opus mid**. Divergent breadth over a repo, run N-wide
    ///   in `team`; mid is where breadth stops being rate-limited by cost.
    /// - `.architecture` is **Opus xhigh** — the single dearest tier in the
    ///   table, because it is the phase whose mistakes are paid for by every
    ///   phase after it. `.archOptions` sits a notch lower at high: an option
    ///   that loses costs nothing, the DECISION is what has to be right.
    /// - `.implement` is **Opus xhigh** — xhigh is the level tuned for coding
    ///   and agentic loops, and this is the only phase that is one.
    /// - `.done` is **Sonnet mid**, and it is the one place this table departs
    ///   from "Opus high for the primary". Sealing a finished prompt is
    ///   bookkeeping against a record that already exists. Flagged as the first
    ///   thing to argue about: if `.done` ever grows a summarisation duty, it
    ///   belongs back on Opus.
    public static func choice(
        for phase: WorkflowSpec.Phase,
        methodology: ExplorationAgentType? = nil
    ) -> GmAgentModelChoice {
        _ = methodology  // See the type's note: a declared axis, deliberately flat.
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

    /// The preset for a role, for callers holding no phase.
    ///
    /// The two non-workflow roles are the interesting rows: `kbiteChewer` and
    /// `mawFetcher` both run over BULK external material with a fixed output
    /// shape, which is the same retrieval-shaped job that puts the doper on
    /// Haiku. They are also the two roles most likely to be run hundreds of
    /// times in a sitting.
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

    /// Every phase and the tier it resolves to, in workflow order for a variant.
    /// For inspection while we tune this — print it, read it, move a row.
    public static func table(for variant: BotVariant) -> [(WorkflowSpec.Phase, GmAgentModelChoice)] {
        WorkflowSpec.phases(for: variant).map { ($0, choice(for: $0)) }
    }
}

extension WorkflowSpec.Phase {

    /// The preset driving this phase. Sugar over
    /// ``GmAgentModelChoiceConfig/choice(for:methodology:)`` — the table stays
    /// the one place the assignment is written.
    public var modelChoice: GmAgentModelChoice {
        GmAgentModelChoiceConfig.choice(for: self)
    }
}
