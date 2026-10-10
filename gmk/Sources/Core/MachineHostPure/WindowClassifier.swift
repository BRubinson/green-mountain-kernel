import Foundation

/// Whether a window takes a column, is left where the user put it, or is not a window at all.
enum WindowClass: Equatable, Sendable {
    /// The window tiles into its workspace strip.
    case tiled
    /// The window is observed but never moved by layout.
    case floating
    /// Not a real window; never tracked, re-tested every reconcile.
    case popup
}

/// The accessibility facts the classifier reads for one window.
///
/// The shell reads the button and focus fields only when the subrole is not `AXStandardWindow`; for a
/// standard window only `fullscreenButtonEnabled` matters.
struct WindowFacts: Equatable, Sendable {
    /// The `AXRole` value, or nil when the app did not answer.
    var role: String?
    /// The `AXSubrole` value, or nil when the app did not answer.
    var subrole: String?
    /// The `AXTitle` value, or nil when the window reports none.
    var title: String?
    /// The `AXFullScreen` value.
    var isFullscreen = false
    /// True when the window has a close button.
    var hasCloseButton = false
    /// True when the window has a zoom button.
    var hasZoomButton = false
    /// True when the window has a minimize button.
    var hasMinimizeButton = false
    /// True when the window has a fullscreen button.
    var hasFullscreenButton = false
    /// True when the window's fullscreen button is present and enabled.
    var fullscreenButtonEnabled = false
    /// The window's `AXFocused` value, or nil when it could not be read.
    var isFocused: Bool?
    /// The window's `AXMain` value, or nil when it could not be read.
    var isMain: Bool?
    /// True when the app's `AXFocusedWindow` is this window.
    var isAppFocusedWindow = false
    /// The owning app's bundle identifier, when it has one.
    var bundleId: String?
    /// True when the owning app runs with the accessory activation policy.
    var isAccessoryApp = false
}

/// Decides from accessibility facts whether a window tiles, floats or is a popup.
enum WindowClassifier {
    /// The subrole of an ordinary document window.
    private static let standardSubrole = "AXStandardWindow"

    /// Apps whose real windows lack an enabled fullscreen button yet still tile.
    static let tilesWithoutFullscreenButton: Set<String> = [
        "org.gimp.gimp-2.10",
        "com.google.Chrome",
        "com.apple.ActivityMonitor",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.qutebrowser.qutebrowser",
        "com.googlecode.iterm2",
        "org.gnu.Emacs",
        "com.microsoft.VSCode",
        "com.vscodium",
        "com.valvesoftware.steam.helper",
    ]

    /// The class of the window the facts describe.
    ///
    /// Minimized is not an input: the reducer stashes a minimized window whatever its class.
    ///
    /// - Parameter facts: The window's accessibility facts.
    /// - Returns: `.popup` for a non-window, `.floating` for a fullscreen window or a dialog, else `.tiled`.
    static func classify(_ facts: WindowFacts) -> WindowClass {
        guard isWindow(facts) else { return .popup }
        if facts.isFullscreen { return .floating }
        return isDialog(facts) ? .floating : .tiled
    }

    /// True when the facts describe a real window rather than a popup, menu or tooltip.
    ///
    /// A buttonless window read as neither focused nor main, with no standard subrole and an empty or
    /// "Window" title, is a popup; an unreadable focus field never counts as unfocused. A window of an
    /// accessory app with no close button is a popup, as is an iTerm2 window with no fullscreen button.
    ///
    /// - Parameter facts: The window's accessibility facts.
    /// - Returns: Whether the window is a real window.
    static func isWindow(_ facts: WindowFacts) -> Bool {
        guard facts.role == "AXWindow" else { return false }
        if facts.isAccessoryApp, !facts.hasCloseButton, facts.bundleId != "com.valvesoftware.steam.helper" {
            return false
        }
        if facts.bundleId == "com.googlecode.iterm2", !facts.hasFullscreenButton { return false }
        let subrole = facts.subrole
        let buttonless =
            !facts.hasCloseButton && !facts.hasFullscreenButton && !facts.hasZoomButton
            && !facts.hasMinimizeButton
        let unfocused = facts.isFocused == false && facts.isMain == false && !facts.isAppFocusedWindow
        let title = facts.title ?? ""
        if buttonless, unfocused, subrole != standardSubrole, title.isEmpty || title == "Window" { return false }
        return subrole == standardSubrole || subrole == "AXDialog" || subrole == "AXFloatingWindow"
            || (facts.bundleId == "com.apple.finder" && subrole == "Quick Look")
    }

    /// True when a real window is a dialog that floats rather than tiles.
    ///
    /// A window with a non-standard subrole is a dialog, as is one without an enabled fullscreen button
    /// unless its app is in `tilesWithoutFullscreenButton`.
    ///
    /// - Parameter facts: The window's accessibility facts.
    /// - Returns: Whether the window floats.
    static func isDialog(_ facts: WindowFacts) -> Bool {
        if facts.subrole != standardSubrole, facts.bundleId != "org.qutebrowser.qutebrowser" { return true }
        let exempt = facts.bundleId.map { tilesWithoutFullscreenButton.contains($0) } ?? false
        return !facts.fullscreenButtonEnabled && !exempt
    }
}
