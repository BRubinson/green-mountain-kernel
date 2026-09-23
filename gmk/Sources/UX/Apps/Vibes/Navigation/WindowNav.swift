import Foundation
import Observation

/// The ONLY per-window navigation state: current route, a shallow back stack,
/// and the global-rail / command-palette flags.
///
/// Created as `@State` at the window root (`GMVibesWindow`) and injected down with `.environment(_:)` — NEVER stored in
/// the process-wide `GMVibesServices` (the LandingWindows per-window-store trap, generalized).
@Observable
@MainActor
final class WindowNav {
    /// `nil` = landing page.
    private(set) var route: Route?
    private var back: [Route?] = []

    /// Global navigation rail; collapsed by default and after a click.
    var railOpen = false
    /// cmd+K action popup.
    var paletteOpen = false
    /// One-shot retarget for the ONE case route identity cannot carry: a
    /// repeat deep link to the prompt the route already names.
    ///
    /// The equality guard in `go` short-circuits there (no re-init), and the
    /// user may have selected a different prompt in-screen meanwhile — so the
    /// live screen consumes this nudge instead. Set exclusively by `open(_:)`
    /// on a route-equal hit; consuming clears it so the next identical hit
    /// registers as a fresh change.
    var pendingPromptTarget: UUID?

    /// Creates a window navigator with the given initial route.
    /// - Parameter initial: The initial route, or nil for the landing page.
    init(initial: Route? = nil) {
        self.route = initial
    }

    var canGoBack: Bool { !back.isEmpty }

    /// Navigates to a session window, opening an editor route if targeted.
    ///
    /// A prompt-targeted id opens the editor route directly — the route IS
    /// the deep link (a different target is a different route identity, so
    /// the screen re-seeds). No target navigates to the session view. The
    /// route-equal repeat rides `pendingPromptTarget`.
    /// - Parameter windowID: The session window to open (may carry a prompt target).
    func open(_ windowID: SessionWindowID) {
        let destination: Route =
            windowID.targetPromptUUID != nil
            ? .sessionPrompt(windowID) : .session(windowID)
        if destination == route, let target = windowID.targetPromptUUID {
            pendingPromptTarget = target
        }
        go(destination)
    }

    /// Navigates to a new route, pushing the current route onto the back stack.
    /// - Parameter newRoute: The route to navigate to.
    func go(_ newRoute: Route) {
        guard newRoute != route else { railOpen = false; return }
        back.append(route)
        route = newRoute
        railOpen = false
    }

    /// Pops the previous route from the back stack and navigates to it.
    func goBack() {
        guard let previous = back.popLast() else { return }
        route = previous
    }

    /// Clears navigation history and returns to the landing page.
    func home() {
        // Landing is the root: going home clears the trail rather than
        // growing a stack nothing will ever unwind.
        back.removeAll()
        route = nil
        railOpen = false
    }
}
