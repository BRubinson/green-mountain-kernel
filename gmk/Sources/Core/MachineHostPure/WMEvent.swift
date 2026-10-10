import CoreGraphics
import Foundation

/// One window as the shell observed it, in global Cocoa coordinates.
struct ObservedWindow: Equatable, Sendable {
    /// The window's identity.
    let key: WindowKey
    /// The window's current frame.
    let frame: CGRect
    /// Whether the window may tile.
    let classification: WindowClass
    /// The window's title, when it reports one.
    let title: String?
    /// The window's `AXMinimized` value.
    var isMinimized = false
}

/// Every input the reducer accepts.
///
/// Frames are global Cocoa coordinates. The shell never sends the app's own windows.
enum WMEvent: Equatable, Sendable {
    /// Turns window management on with the strips and visible workspace per display key; the hotkeys are
    /// `KeyCodeTable.bindings`.
    case enable(strips: [WorkspaceStrip], active: [String: String])
    /// Applies an edited configuration while enabled, moving only the windows whose placement changed.
    case configure(strips: [WorkspaceStrip], active: [String: String])
    /// Turns window management off and returns every parked window.
    case disable
    /// A registered hotkey fired.
    case hotkey(HotkeyBinding)
    /// A GUI process launched; its bundle id is recorded even while disabled.
    case appLaunched(pid: Int32, launchedAt: Date, bundleId: String?)
    /// A GUI process terminated.
    case appTerminated(pid: Int32)
    /// A window appeared; a minimized one is stashed until it returns.
    case windowCreated(
        WindowKey,
        frame: CGRect,
        classification: WindowClass,
        title: String?,
        isMinimized: Bool = false
    )
    /// A window closed.
    case windowDestroyed(WindowKey)
    /// A window took keyboard focus.
    case windowFocused(WindowKey)
    /// Native focus is on a window the shell cannot key, or on no window.
    case focusUnmanaged
    /// A window's origin changed.
    case windowMoved(WindowKey, CGRect)
    /// A window's size changed.
    case windowResized(WindowKey, CGRect)
    /// A window was minimized to the Dock.
    case windowMinimized(WindowKey)
    /// A minimized window returned, at `frame` and re-classified.
    case windowDeminimized(WindowKey, frame: CGRect, classification: WindowClass)
    /// An app was hidden.
    case appHidden(pid: Int32)
    /// A hidden app was shown again.
    case appUnhidden(pid: Int32)
    /// Replaces every per-app rule, keyed by bundle id; accepted even while disabled.
    case rulesReplaced([String: WindowClass])
    /// The left mouse button went down at `at`; layout freezes until it goes up.
    case mousePressed(at: CGPoint)
    /// The left mouse button went up at `at`; nil when the release was seen late and has no drop point.
    case mouseReleased(at: CGPoint?)
    /// The display arrangement changed; the payload is every connected display.
    case displaysChanged([DisplayGeom])
    /// The machine woke from sleep.
    case wake
    /// A snapshot of every observed window; only windows of the `answered` pids may be found missing.
    ///
    /// `hidden` holds the pids whose app is hidden; `unreadable` holds windows whose id read but whose frame
    /// did not, which are never destroyed.
    case reconcile(
        observed: [ObservedWindow],
        answered: Set<Int32>,
        hidden: Set<Int32> = [],
        unreadable: Set<WindowKey> = []
    )
}
