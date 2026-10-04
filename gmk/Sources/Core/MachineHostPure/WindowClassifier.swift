import Foundation

/// Whether a window takes a column or is left where the user put it.
enum WindowClass: Equatable, Sendable {
    /// The window tiles into its workspace strip.
    case tiled
    /// The window is observed but never moved by layout.
    case floating
}

/// Decides from accessibility attributes whether a window tiles.
enum WindowClassifier {
    /// The class of a window with the given accessibility role, subrole and state.
    ///
    /// Only a standard, visible, windowed window tiles; dialogs, sheets, panels, minimized and
    /// fullscreen windows float.
    ///
    /// - Parameters:
    ///   - role: The `AXRole` value, or nil when the app did not answer.
    ///   - subrole: The `AXSubrole` value, or nil when the app did not answer.
    ///   - isMinimized: The `AXMinimized` value.
    ///   - isFullscreen: The `AXFullScreen` value.
    /// - Returns: `.tiled` for a standard window, else `.floating`.
    static func classify(role: String?, subrole: String?, isMinimized: Bool, isFullscreen: Bool) -> WindowClass {
        guard role == "AXWindow", subrole == "AXStandardWindow", !isMinimized, !isFullscreen else {
            return .floating
        }
        return .tiled
    }
}
