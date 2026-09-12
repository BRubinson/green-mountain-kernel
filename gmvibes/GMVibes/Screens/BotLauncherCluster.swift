import SwiftUI

/// The prompt editor's resume-command launcher: three copy buttons (one per
/// bot fidelity tier) plus the inline picker that sets which tier is the
/// persisted default.
///
/// **All three copy buttons stay.** An explicit copy is always exactly one
/// click, whatever the default is — the picker changes which tier is
/// highlighted and which one a choice-less `copyResume()` emits, never which
/// tiers are reachable.
///
/// **The default is set explicitly, never learned.** Clicking a copy button
/// copies and nothing else; it does not re-point the preference. Trying
/// `/gm_bot` once must not silently become your default. That is the whole
/// behavioural contract of Feature 1, and it is why the highlight is bound to
/// `BotLauncherPreference` rather than to a `@State` selection.
///
/// GMVibes has no channel into the session it launches, so there is
/// deliberately nothing here about reconcile behavior or per-role
/// model/effort — no stub, no disabled control, no "coming soon". A disabled
/// control is a promise this architecture cannot keep.
struct BotLauncherCluster: View {
    /// The prompt's daemon-allocated per-session seq — bot commands resolve
    /// prompts by seq, not uuid.
    let seq: Int

    /// The one piece of persisted state Feature 1 adds. Bound straight to the
    /// picker, so setting the default IS the write; no sheet, no save button.
    @AppStorage(BotLauncherPreference.key) private var defaultTier = BotLauncherPreference.fallback

    var body: some View {
        ControlGroup {
            ForEach(BotTier.allCases) { tier in
                Button { copyResume(tier) } label: {
                    Label(tier.command, systemImage: symbol(tier))
                }
                // The highlight tracks the PERSISTED default, so it means the
                // same thing in every window — unlike the per-window
                // last-clicked state it replaces.
                .tint(tier == defaultTier ? .accentColor : nil)
                .help(help(for: tier))
            }
            defaultPicker
        } label: {
            Label("Resume Command", systemImage: defaultTier.symbol)
        }
    }

    // MARK: - The explicit default

    // Inline on the cluster, next to the copy buttons where it takes effect —
    // the settled decision was no settings sheet anywhere in this prompt.
    private var defaultPicker: some View {
        Picker(selection: $defaultTier) {
            ForEach(BotTier.allCases) { tier in
                Text("\(tier.command) — \(tier.phaseCount) phases").tag(tier)
            }
        } label: {
            Label("Default tier", systemImage: "gearshape")
        }
        .pickerStyle(.menu)
        .help("Default bot tier — \(defaultTier.command), \(defaultTier.phaseCount) phases")
    }

    // MARK: - Copy

    /// Puts a tier's resume command on the pasteboard. Called with an explicit
    /// tier by each copy button; the persisted default supplies the tier when
    /// it is invoked without a choice.
    ///
    /// Copying does NOT touch the preference — see the type's doc comment.
    private func copyResume(_ tier: BotTier? = nil) {
        Clipboard.copy((tier ?? defaultTier).command(for: seq))
    }

    // MARK: - Chrome

    // Filled icon for the default tier, outline for the rest (person /
    // person.2 / person.3 — 1/2/3-person crews by fidelity).
    private func symbol(_ tier: BotTier) -> String {
        tier == defaultTier
            ? tier.symbol
            : tier.symbol.replacingOccurrences(of: ".fill", with: "")
    }

    // Phase counts come from the daemon kit's WorkflowSpec, so the help text
    // describes the machine the run will actually walk.
    private func help(for tier: BotTier) -> String {
        let base = "Copy \(tier.command(for: seq)) to the clipboard — \(tier.phaseCount) phases"
        return tier == defaultTier ? base + " (default)" : base
    }
}
