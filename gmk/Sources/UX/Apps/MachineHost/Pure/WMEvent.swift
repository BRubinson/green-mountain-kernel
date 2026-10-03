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
    /// A GUI process launched.
    case appLaunched(pid: Int32, launchedAt: Date)
    /// A GUI process terminated.
    case appTerminated(pid: Int32)
    /// A window appeared.
    case windowCreated(WindowKey, frame: CGRect, classification: WindowClass, title: String?)
    /// A window closed.
    case windowDestroyed(WindowKey)
    /// A window took keyboard focus.
    case windowFocused(WindowKey)
    /// A window's origin changed.
    case windowMoved(WindowKey, CGRect)
    /// A window's size changed.
    case windowResized(WindowKey, CGRect)
    /// The left mouse button went down at `at`; layout freezes until it goes up.
    case mousePressed(at: CGPoint)
    /// The left mouse button went up at `at`; nil when the release was seen late and has no drop point.
    case mouseReleased(at: CGPoint?)
    /// The display arrangement changed; the payload is every connected display.
    case displaysChanged([DisplayGeom])
    /// The machine woke from sleep.
    case wake
    /// A snapshot of every observed window; only windows of the `answered` pids may be found missing.
    case reconcile(observed: [ObservedWindow], answered: Set<Int32>)
}
