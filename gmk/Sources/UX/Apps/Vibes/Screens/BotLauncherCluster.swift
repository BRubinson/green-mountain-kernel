import SwiftUI

/// The prompt editor's resume-command launcher: one copy button per bot fidelity tier, plus
/// the inline picker that sets the persisted default.
///
/// Every tier stays reachable in one click. The picker changes which tier is highlighted and
/// which one a choice-less `copyResume()` emits, and THE DEFAULT IS SET EXPLICITLY: clicking a
/// copy button copies and nothing else, so trying a tier once never re-points the preference.
/// That is why the highlight binds to `BotLauncherPreference` rather than a `@State` selection.
/// The app has no channel into the session it launches, so nothing here promises one.
struct BotLauncherCluster: View {
    /// The prompt's daemon-allocated per-session seq — bot commands resolve
    /// prompts by seq, not uuid.
    let seq: Int

    /// The one piece of persisted state Feature 1 adds.
    ///
    /// Bound straight to the picker, so setting the default IS the write; no sheet, no save button.
    @AppStorage(BotLauncherPreference.key) private var defaultTier = BotLauncherPreference.fallback

    var body: some View {
        ControlGroup {
            ForEach(BotTier.allCases) { tier in
                Button {
                    copyResume(tier)
                } label: {
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

    /// Copies a tier's resume command to the pasteboard.
    ///
    /// Explicit tier comes from each copy button; the persisted default
    /// supplies the tier when invoked without a choice. Copying does not
    /// touch the preference.
    /// - Parameter tier: The bot tier to copy, or nil for the default tier.
    private func copyResume(_ tier: BotTier? = nil) {
        Clipboard.copy((tier ?? defaultTier).command(for: seq))
    }

    // MARK: - Chrome

    /// Returns the symbol for a tier with fill or outline based on default.
    /// - Parameter tier: The bot tier.
    /// - Returns: The SF symbol name (filled for default, outlined for others).
    private func symbol(_ tier: BotTier) -> String {
        tier == defaultTier
            ? tier.symbol
            : tier.symbol.replacingOccurrences(of: ".fill", with: "")
    }

    /// Generates help text describing a tier's phase count.
    /// - Parameter tier: The bot tier to describe.
    /// - Returns: Help text with the tier name, phase count, and default flag.
    private func help(for tier: BotTier) -> String {
        let base = "Copy \(tier.command(for: seq)) to the clipboard — \(tier.phaseCount) phases"
        return tier == defaultTier ? base + " (default)" : base
    }
}
