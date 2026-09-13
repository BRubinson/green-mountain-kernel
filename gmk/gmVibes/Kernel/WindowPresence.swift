import AppKit

/// Dock presence follows OPEN WINDOWS, not the process.
///
/// `INFOPLIST_KEY_LSUIElement = YES` is what keeps the resident kernel out of
/// the Dock and out of ⌘-Tab. That is right for the half of this process that
/// is a background service and WRONG for every window it opens, because the
/// plist key is a PROCESS-WIDE switch and the process is two things at once.
///
/// The cost is not cosmetic. An accessory process is not a regular app in the
/// window server's eyes, so its windows get no Dock entry, no ⌘-Tab slot and no
/// main menu — and tiling window managers read the activation policy to decide
/// what they may manage, so every GM Vibes window arrived as an unmanaged
/// floating panel. AeroSpace tiles the same window correctly the instant the
/// policy is raised, which is what identifies the policy (rather than anything
/// about the window itself) as the cause.
///
/// So the plist value STAYS — launch is silent, and a login that popped a Dock
/// icon for a background service is the regression this app was careful to
/// avoid — and the policy is raised for exactly as long as a window is on
/// screen. Windows are COUNTED, not flagged: `WindowSeed`'s per-open UUID makes
/// `WindowGroup` dedupe structurally impossible, so many windows can be open at
/// once and the policy must retire on the last close, not the first.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()

    private var openWindows = 0

    private init() {}

    /// Balanced against window lifetime by the caller's `.task`.
    func acquire() {
        openWindows += 1
        guard openWindows == 1 else { return }
        NSApp.setActivationPolicy(.regular)
        // Raising the policy does not focus the app. AppKit grants the Dock
        // entry and the main menu and leaves the window behind whatever the
        // user was in — the same failure the menu bar's New Window item guards
        // against, one layer down, and it reads as "the window never opened".
        NSApp.activate()
    }

    func release() {
        openWindows -= 1
        guard openWindows == 0 else { return }
        // One turn of the run loop before demoting. Closing the last window and
        // opening another (New Window from the menu bar, or a route that tears
        // its window down) passes through zero on the way, and demoting there
        // drops the Dock icon and takes it straight back — AppKit renders that
        // as a visible flicker and a lost activation.
        Task { @MainActor in
            guard self.openWindows == 0 else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
