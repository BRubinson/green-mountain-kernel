import SwiftUI
import GMCCDaemonKit

/// The ONLY lifecycle chrome in the app: the status chip plus exactly two
/// controls — **Mark done** and **Back to Draft**. It replaces the six-state
/// lifecycle rail, which was deleted outright; there is no fallback rail and
/// no second progress surface anywhere.
///
/// ### Why both actions
/// The workflow options were written against a care-package intent saying
/// Back to Draft is removed. The user reversed that mid-flight ("okay keep
/// back o draft too"). **Back to Draft is kept**: the chip carries BOTH
/// actions, `PromptStatus.allowedNext` and the `Gate` enum survive wholesale
/// from the deleted lifecycle rail rather than being narrowed to the Done
/// edge, and the app retains a status-reversal affordance (blocked today — the daemon has
/// no backward edge — and it ships visible-but-disabled so the intent reads
/// as "coming", not "missing").
///
/// ### Why this type is independent of the strip
/// The chip and both actions render from `stub.status` +
/// `PromptStatus.allowedNext` ALONE. This view never reads `phases.workflow`
/// — `WorkflowStrip` is its SIBLING at the call site, not its parent and not
/// its child. That is the structural reason deleting the rail is safe: the
/// strip can fail completely, render nothing at all, or be wrong about a
/// variant this build has never heard of, and the lifecycle controls still
/// work. When the prompt has no `bot_workflow` row (never started, and
/// `/gm_task` where the absence is permanent) this header renders ALONE —
/// no strip, no empty state, no distinguishing copy.
///
/// `phases` is taken for ONE reason: `transition(to:)`'s `invalidTransition`
/// arm resyncs it, exactly as the deleted lifecycle rail did. It is never
/// consulted for rendering or gating.
///
/// A daemon `INVALID_TRANSITION` is a lost race — its reason string
/// (preserved by `DaemonError.invalidTransition(reason:)`) surfaces verbatim.
struct PromptStatusHeader: View {
    let stub: PromptStub
    let phases: PromptPhaseStore
    let store: SessionStore

    @State private var transitionError: String?
    @State private var inFlight = false

    private var status: PromptStatus? { PromptStatus(rawValue: stub.status) }

    /// Lifted verbatim from the deleted lifecycle rail.
    enum Gate {
        case open
        case blocked(reason: String, fix: String)
        /// The client can't adjudicate — offer the button; the daemon rules
        /// and `invalidTransition(reason:)` surfaces the real message.
        case unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PromptStatusBadge(status: status)
                Spacer()
                if inFlight {
                    ProgressView().controlSize(.small)
                }
                transitionButton(to: .done)
                transitionButton(to: .draft)
            }
            if let transitionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(transitionError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { self.transitionError = nil }
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                }
            } else if let hint = blockedHint {
                // The gate reason is the only explanation for a dead primary
                // affordance — visible text, not just a hover tooltip.
                Label(hint, systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 10))
    }

    private var blockedHint: String? {
        // `.done` ONLY: Back to Draft is permanently blocked, so consulting
        // every button would render its message forever and mask the Done
        // reason — the one explanation the user actually needs. A done
        // prompt is terminal and needs no hint.
        guard let status, status != .done else { return nil }
        if case .blocked(let reason, let fix) = gate(to: .done) {
            return "\(reason) — \(fix)."
        }
        return nil
    }

    // MARK: - Transitions

    @ViewBuilder
    private func transitionButton(to next: PromptStatus) -> some View {
        let gate = gate(to: next)
        Button {
            Task { await transition(to: next) }
        } label: {
            Label(buttonTitle(for: next), systemImage: buttonIcon(for: next))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(inFlight || isBlocked(gate))
        .help(helpText(for: next, gate: gate))
    }

    private func isBlocked(_ gate: Gate) -> Bool {
        if case .blocked = gate { return true }
        return false
    }

    private func helpText(for next: PromptStatus, gate: Gate) -> String {
        if case .blocked(let reason, let fix) = gate {
            return "\(reason) — \(fix)"
        }
        return "Advance this prompt to \(next.rawValue)"
    }

    /// `PromptStatus.allowedNext` is the authority, consulted for `.done`;
    /// `.draft` has no daemon-side edge at all. The old rail's forward-edge
    /// branches (clarifying→architecting, architecting→implementing) went with
    /// the `precomputed*Gate` helpers: they adjudicated edges the rail never
    /// offered, and that file's own comment called them unreachable.
    private func gate(to next: PromptStatus) -> Gate {
        switch next {
        case .done:
            // The EDGE SET rules here, not a phase gate: the daemon couples
            // no summary requirement to →done, but .done has exactly two
            // inbound edges (implementing, reviewing) — server-enforced.
            guard let status else { return .unknown }
            // A done prompt is terminal. The old rail expressed this by
            // rendering NO buttons at all (`nextStates` returned []); this
            // header always renders both controls, so the terminal state
            // becomes an honest gate reason instead of the self-contradicting
            // "advance the prompt first" the old edge copy would produce.
            guard status != .done else {
                return .blocked(reason: "This prompt is already done",
                                fix: "there is nothing left to advance")
            }
            guard status.allowedNext.contains(.done) else {
                return .blocked(
                    reason: "Done is reachable from Implementing or Reviewing (this prompt is \(status.rawValue))",
                    fix: "advance the prompt with the bot first")
            }
            return .open
        case .draft:
            // No backward edge exists daemon-side — filed as a GM feature
            // request; the button ships visible-but-disabled so the intent
            // reads as "coming", not "missing". KEPT per the user's
            // mid-flight correction.
            return .blocked(
                reason: "Back to Draft isn't available yet",
                fix: "pending a GM feature (the daemon has no backward edge)")
        default:
            return .open
        }
    }

    private func buttonTitle(for next: PromptStatus) -> String {
        switch next {
        case .done: "Mark done"
        case .draft: "Back to Draft"
        default: "Advance to \(next.rawValue.capitalized)"
        }
    }

    private func buttonIcon(for next: PromptStatus) -> String {
        switch next {
        case .done: "checkmark.circle"
        case .draft: "arrow.uturn.backward.circle"
        default: "arrow.right.circle"
        }
    }

    private func transition(to next: PromptStatus) async {
        inFlight = true
        transitionError = nil
        defer { inFlight = false }
        // Land any pending draft FIRST: a click inside the 2s autosave window
        // must not strand the user's last edit against a freshly-locked
        // prompt. The flush may advance the version, so re-read it.
        await PromptFlushRegistry.shared.flushAll()
        await store.refreshPrompt(uuid: stub.uuid)
        let version = store.prompts.first(where: { $0.uuid == stub.uuid })?.version ?? stub.version
        do {
            _ = try await GMCCDaemonService.shared.setPromptStatus(PromptSetStatusRequest(
                promptUuid: stub.uuid,
                expectedVersion: version,
                status: next
            ))
            await store.refreshPrompt(uuid: stub.uuid)
            await store.refresh()
        } catch let error as DaemonError {
            switch error {
            case .invalidTransition:
                // Lost race (a bot advanced between render and click) — show
                // the daemon's reason and resync both the prompt and the
                // prompt's phase reads.
                transitionError = error.userMessage
                await store.refreshPrompt(uuid: stub.uuid)
                await phases.refresh()
            case .versionConflict:
                transitionError = "The prompt changed elsewhere — reloaded; try again."
                await store.refreshPrompt(uuid: stub.uuid)
            default:
                transitionError = error.userMessage
            }
        } catch {
            transitionError = String(describing: error)
        }
    }
}
