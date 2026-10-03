import CoreGraphics
import Foundation

/// The identity of one managed window: its process, that process's launch, and its CoreGraphics id.
///
/// `launchedAt` makes a recycled pid a different key, so a new process never inherits the rows of a dead one.
struct WindowKey: Hashable, Sendable {
    /// The owning process id.
    let pid: Int32
    /// The owning process's launch date, which disambiguates a reused pid.
    let launchedAt: Date
    /// The window's CoreGraphics id, stable for the life of the window.
    let cgWindowId: UInt32
}

/// One connected display, in global Cocoa coordinates (bottom-left origin).
struct DisplayGeom: Equatable, Sendable {
    /// The stable display key (the CoreGraphics display UUID string).
    let key: String
    /// The full screen frame.
    let frame: CGRect
    /// The frame minus the menu bar and the Dock; columns tile this rectangle.
    let visibleFrame: CGRect
    /// True for the display that carries the menu bar.
    let isMain: Bool
}

/// One tiled window in a workspace strip, with its share of the strip's width.
struct StripColumn: Equatable, Sendable {
    /// The tiled window.
    let window: WindowKey
    /// The relative width weight; the column's width is `visibleWidth × weight / Σweight`.
    var weight: Double
}

/// A workspace: a left-to-right strip of columns shown on one display at a time.
struct WorkspaceStrip: Equatable, Sendable {
    /// The workspace code, one of `MachineHostPlacement.WorkspaceCodes.all` ("1", "Q").
    let code: String
    /// The display the active workstation places the strip on; it stays hidden while that display is gone.
    var displayKey: String
    /// The tiled windows, left to right.
    var columns: [StripColumn]
    /// The index of the focused column, or nil when the strip is empty.
    var focusedIndex: Int?

    /// Creates a strip placed on a display.
    ///
    /// - Parameters:
    ///   - code: The workspace code.
    ///   - displayKey: The key of the display the strip is placed on.
    ///   - columns: The initial columns, left to right.
    ///   - focusedIndex: The focused column, or nil to focus the first column when there is one.
    init(code: String, displayKey: String, columns: [StripColumn] = [], focusedIndex: Int? = nil) {
        self.code = code
        self.displayKey = displayKey
        self.columns = columns
        self.focusedIndex = focusedIndex ?? (columns.isEmpty ? nil : 0)
    }

    /// The column weights, left to right.
    var weights: [Double] { columns.map(\.weight) }
}

/// What a global hotkey does; the raw value is the action's stable name.
enum HotkeyAction: String, Sendable, CaseIterable {
    /// Shows the bound workspace on its display.
    case focusWorkspace = "focus_workspace"
    /// Moves the focused window to the bound workspace.
    case moveToWorkspace = "move_to_workspace"
    /// Focuses the column to the left.
    case focusLeft = "focus_left"
    /// Focuses the column to the right.
    case focusRight = "focus_right"
    /// Swaps the focused column with its left neighbour.
    case slideLeft = "slide_left"
    /// Swaps the focused column with its right neighbour.
    case slideRight = "slide_right"
    /// Widens the focused column by the binding's step.
    case resizeGrow = "resize_grow"
    /// Narrows the focused column by the binding's step.
    case resizeShrink = "resize_shrink"
}

/// One chord bound to one action, as registered with the system.
struct HotkeyBinding: Hashable, Sendable {
    /// The Carbon virtual key code of the physical key.
    let keyCode: UInt32
    /// The Carbon modifier mask (see `ModifierMask`).
    let modifiers: UInt32
    /// What the chord does.
    let action: HotkeyAction
    /// The target workspace for `focusWorkspace` and `moveToWorkspace`, else nil.
    let workspaceCode: String?
    /// The step in points for the resize actions, else nil.
    let resizeStep: Double?
}

/// What a mouse drag turned out to be, decided once from the frames it produced.
enum DragMode: Equatable, Sendable {
    /// Neither the width nor the position has changed enough to tell.
    case undecided
    /// The window travels at a constant width; its strip reorders under the pointer.
    case move
    /// The window's width changed; the release re-weights it against a neighbour.
    case resize
}

/// A tiled window the user is moving or resizing with the mouse; the release settles it once.
struct MouseDrag: Equatable, Sendable {
    /// The window under the pointer; no effect writes its frame until the button goes up.
    let window: WindowKey
    /// The frame the reducer last placed the window at when the drag began.
    let startFrame: CGRect
    /// The window's last known frame when the drag began, which the move threshold is measured from.
    let originFrame: CGRect
    /// The left edge the window's reorder displacement is measured from; it follows the window's slot.
    var slotOriginX: CGFloat
    /// The neighbour the window last swapped places with, which takes a longer travel to pass back.
    var lastPassed: WindowKey?
    /// The width of the first frame observed during the drag; nil until one arrives.
    var baseWidth: CGFloat?
    /// The latest frame observed for the window during the drag.
    var latestFrame: CGRect
    /// Whether the drag moves or resizes the window.
    var mode: DragMode = .undecided

    /// How far the window's left edge has travelled from its slot; positive is right.
    var displacement: CGFloat { latestFrame.minX - slotOriginX }
}

/// A configuration edit held back while the mouse button is down.
struct WMConfiguration: Equatable, Sendable {
    /// Every workspace, in configuration order.
    let strips: [WorkspaceStrip]
    /// The visible workspace code per display key; it replaces what the reducer shows on those displays.
    let active: [String: String]
}

/// The whole window-manager state the reducer folds events into.
struct WMState: Equatable, Sendable {
    /// The connected displays.
    var displays: [DisplayGeom] = []
    /// Every workspace strip, keyed by code.
    var workspaces: [String: WorkspaceStrip] = [:]
    /// Workspace codes in configuration order; ties in active-workspace choice go to the earliest.
    var workspaceOrder: [String] = []
    /// The visible workspace code per display key.
    var activeByDisplay: [String: String] = [:]
    /// The pre-park frame of every parked window.
    var parked: [WindowKey: CGRect] = [:]
    /// Windows that are observed but never tiled.
    var floating: Set<WindowKey> = []
    /// The window that holds keyboard focus, when it is one of ours.
    var focused: WindowKey?
    /// The workspace last focused, which hotkeys act on when it is shown and holds no focused window.
    var focusedWorkspace: String?
    /// The last frame the reducer asked for per window; a match is the echo of its own write.
    var expectedFrames: [WindowKey: CGRect] = [:]
    /// The last known frame per window, observed or requested.
    var frames: [WindowKey: CGRect] = [:]
    /// The last reported title per window.
    var titles: [WindowKey: String] = [:]
    /// The tiled window held by the mouse, from its first dragged move or resize until the button goes up.
    var mouseDrag: MouseDrag?
    /// True while the left mouse button is down; no visible strip is laid out until it goes up.
    var mouseHeld = false
    /// Where the left mouse button went down, while it is held.
    var pressPoint: CGPoint?
    /// The visible strips whose layout was held back while the button was down.
    var relayoutOnRelease: Set<String> = []
    /// True when a display change arrived while the button was down and awaits the release.
    var displaysPendingRelease = false
    /// The latest configuration edit that arrived while the button was down.
    var configurationPendingRelease: WMConfiguration?
    /// True while window management is on.
    var enabled = false
}

extension WMState {
    /// The display carrying the menu bar, else the first display, or nil when none is connected.
    var mainDisplay: DisplayGeom? { displays.first(where: \.isMain) ?? displays.first }

    /// The connected display with `key`, or nil when it is not connected.
    ///
    /// - Parameter key: The stable display key.
    /// - Returns: The display, or nil.
    func display(forKey key: String) -> DisplayGeom? {
        displays.first { $0.key == key }
    }

    /// The code of the strip that tiles `window`, or nil when no strip holds it.
    ///
    /// - Parameter window: The window to find.
    /// - Returns: The workspace code, or nil.
    func stripCode(containing window: WindowKey) -> String? {
        workspaces.values.first { strip in strip.columns.contains { $0.window == window } }?.code
    }

    /// True when the strip `code` is the visible workspace on its display.
    ///
    /// - Parameter code: The workspace code.
    /// - Returns: Whether the strip is shown.
    func isActive(_ code: String) -> Bool {
        guard let strip = workspaces[code] else { return false }
        return activeByDisplay[strip.displayKey] == code
    }

    /// The strip hotkeys act on: the focused window's, else the last focused shown one, else the main display's.
    var currentStripCode: String? {
        if let focused, let code = stripCode(containing: focused) { return code }
        if let focusedWorkspace, isActive(focusedWorkspace) { return focusedWorkspace }
        guard let main = mainDisplay else { return nil }
        return activeByDisplay[main.key]
    }

    /// True when `window` is tiled in some strip or tracked as floating.
    ///
    /// - Parameter window: The window to look up.
    /// - Returns: Whether the reducer knows the window.
    func knows(_ window: WindowKey) -> Bool {
        floating.contains(window) || stripCode(containing: window) != nil
    }

    /// Every window the reducer tracks, tiled or floating.
    var allWindows: Set<WindowKey> {
        floating.union(workspaces.values.flatMap { $0.columns.map(\.window) })
    }
}
