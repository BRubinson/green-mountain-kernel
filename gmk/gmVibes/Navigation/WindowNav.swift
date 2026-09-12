import Foundation
import Observation

/// The ONLY per-window navigation state: current route, a shallow back stack,
/// and the global-rail / command-palette flags. Created as `@State` at the
/// window root (`GMVibesWindow`) and injected down with `.environment(_:)` —
/// NEVER stored in the process-wide `GMVibesServices` (the LandingWindows
/// per-window-store trap, generalized).
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
    /// repeat deep link to the prompt the route already names. `go`'s
    /// equality guard short-circuits there (no re-init), and the user may
    /// have selected a different prompt in-screen meanwhile — so the live
    /// screen consumes this nudge instead. Set exclusively by `open(_:)` on
    /// a route-equal hit; consuming clears it so the next identical hit
    /// registers as a fresh change.
    var pendingPromptTarget: UUID?

    init(initial: Route? = nil) {
        self.route = initial
    }

    var canGoBack: Bool { !back.isEmpty }

    /// Session navigation: a prompt-targeted id opens the editor route
    /// directly — the route IS the deep link (a different target is a
    /// different route identity, so the screen re-seeds). No target ⇒ the
    /// session view. The route-equal repeat rides `pendingPromptTarget`.
    func open(_ windowID: SessionWindowID) {
        let destination: Route = windowID.targetPromptUUID != nil
            ? .sessionPrompt(windowID) : .session(windowID)
        if destination == route, let target = windowID.targetPromptUUID {
            pendingPromptTarget = target
        }
        go(destination)
    }

    func go(_ newRoute: Route) {
        guard newRoute != route else { railOpen = false; return }
        back.append(route)
        route = newRoute
        railOpen = false
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        route = previous
    }

    func home() {
        // Landing is the root: going home clears the trail rather than
        // growing a stack nothing will ever unwind.
        back.removeAll()
        route = nil
        railOpen = false
    }
}
