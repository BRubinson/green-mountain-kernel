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
public final class WindowPresence {
    public static let shared = WindowPresence()

    private var openWindows = 0
    /// Invalidates a scheduled demotion. See `release()`.
    private var demotionToken = 0

    private init() {}

    /// Raise the policy BEFORE asking for a window — the lease below cannot do
    /// this job on its own, and the failure is invisible until you tile.
    ///
    /// A window's lease is taken from `.task`, which SwiftUI runs AFTER the
    /// view appears: by then the `NSWindow` has been created and ordered on
    /// screen. A window manager classifies a window when it is CREATED, so the
    /// first window of an accessory process is classified as unmanageable and
    /// stays that way — raising the policy afterwards does not make it
    /// re-evaluate a window it has already seen. Every SUBSEQUENT window then
    /// tiles correctly, because by then the process is already `.regular`,
    /// which is exactly the "first one floats, the rest are fine" shape.
    ///
    /// Only the menu bar needs to call this. The zero-window state means no
    /// window exists, so a menu bar item is the ONLY surface that can open one
    /// from there; every other `openWindow` call site already runs inside a
    /// window, where the policy is necessarily raised already.
    public func prepareForWindow() {
        raise()
    }

    /// Balanced against window lifetime by the caller's `.task`.
    func acquire() {
        openWindows += 1
        raise()
    }

    func release() {
        openWindows -= 1
        guard openWindows == 0 else { return }
        // One turn of the run loop before demoting. Closing the last window and
        // opening another (New Window from the menu bar, or a route that tears
        // its window down) passes through zero on the way, and demoting there
        // drops the Dock icon and takes it straight back — AppKit renders that
        // as a visible flicker and a lost activation.
        //
        // The token is what makes that deferral safe. Without it a demotion
        // scheduled by the last close could land AFTER `prepareForWindow` had
        // raised the policy for the next window but BEFORE that window's lease
        // was taken — dropping the process back to accessory at precisely the
        // moment the new window is created, which is the bug this whole type
        // exists to prevent, reintroduced through the back door.
        demotionToken += 1
        let token = demotionToken
        Task { @MainActor in
            guard self.openWindows == 0, self.demotionToken == token else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Idempotent, and it cancels any pending demotion.
    private func raise() {
        demotionToken += 1
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        // The Dock tile exists ONLY from here. Badging is therefore hung off the
        // policy change rather than off launch: under LSUIElement there is no
        // tile to draw on until this moment, which is exactly why the Dock badge
        // is the CONDITIONAL signal and the menu-bar glyph and banner are the
        // always-visible ones.
        EnvironmentDockBadge.apply()
        // Raising the policy does not focus the app. AppKit grants the Dock
        // entry and the main menu and leaves the window behind whatever the
        // user was in — the same failure the menu bar's New Window item guards
        // against, one layer down, and it reads as "the window never opened".
        NSApp.activate()
    }
}
