import CoreGraphics
import Foundation

/// Every side effect the reducer asks of the shell.
///
/// Frames are global Cocoa coordinates.
enum WMEffect: Equatable, Sendable {
    /// Moves and sizes a visible window.
    case setFrame(WindowKey, CGRect)
    /// Hides a window in a display corner; its pre-park frame is recorded in the state.
    case park(WindowKey, CGRect)
    /// Brings a parked window back to the given frame.
    case unpark(WindowKey, CGRect)
    /// Gives a window keyboard focus.
    case focus(WindowKey)
    /// Registers these hotkeys, replacing any registered before.
    case registerHotkeys([HotkeyBinding])
    /// Unregisters every hotkey.
    case unregisterAllHotkeys
    /// The mirror is stale for these windows and processes; `urgent` is true when a pre-park frame changed.
    case mirrorDirty(windows: Set<WindowKey>, processes: Set<Int32>, urgent: Bool)
    /// Records that `workspaceCode` is the visible workspace on the display `displayKey`.
    case persistActiveWorkspace(displayKey: String, workspaceCode: String)
}
