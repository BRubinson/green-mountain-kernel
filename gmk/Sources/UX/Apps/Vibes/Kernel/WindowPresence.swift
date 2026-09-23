import AppKit

/// Dock presence follows OPEN WINDOWS, not the process.
///
/// `INFOPLIST_KEY_LSUIElement = YES` keeps the resident kernel out of the Dock and ⌘-Tab, but
/// it is PROCESS-WIDE: an accessory process's windows get no Dock entry, no ⌘-Tab slot and no
/// main menu, and tiling window managers read the policy to decide what they may manage. So
/// the plist value stays and the policy is raised for as long as a window is on screen.
/// Windows are COUNTED, not flagged, because `WindowSeed`'s per-open UUID makes `WindowGroup`
/// dedupe impossible: the policy retires on the last close, not the first.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()

    private var openWindows = 0
    /// Invalidates a scheduled demotion.
    ///
    /// See `release()`.
    private var demotionToken = 0

    /// Creates the shared window presence manager.
    private init() {}

    /// Raise the policy BEFORE asking for a window.
    ///
    /// The failure is invisible until you tile. A lease is taken from `.task`
    /// (which SwiftUI runs after the `NSWindow` exists); a window manager
    /// classifies windows at CREATION time.
    ///
    /// Only the menu bar needs to call this: it is the only surface that can open a window
    /// from the zero-window state, and every other call site already runs inside one.
    func prepareForWindow() {
        raise()
    }

    /// Acquire a window reference, raising the Dock policy.
    ///
    /// Balanced against window lifetime by the caller's `.task`.
    func acquire() {
        openWindows += 1
        raise()
    }

    /// Release a window reference, demotion the Dock policy if no windows remain.
    func release() {
        openWindows -= 1
        guard openWindows == 0 else { return }
        // One turn of the run loop before demoting: closing the last window and opening
        // another passes through zero, and demoting there drops the Dock icon and takes it
        // straight back as a visible flicker and a lost activation.
        //
        // The token makes the deferral safe. Without it a demotion scheduled by the last close
        // can land after `prepareForWindow` raised the policy but before the next window's
        // lease was taken, dropping to accessory exactly as that window is created.
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
