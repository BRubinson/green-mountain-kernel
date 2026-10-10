import CoreGraphics
import Foundation

/// The two-display reducer fixture shared by the focus, stash and rule tests.
///
/// The main display is 1000 × 800 with a 780pt visible frame; a second 800 × 600 display sits to its right.
/// Workspaces 1 and 2 live on the main display and workspace 3 on the side display.
struct WMFixture {
    /// The launch date of every fixture process.
    let launch = Date(timeIntervalSince1970: 1_700_000_000)
    /// The main display.
    let main = DisplayGeom(
        key: "main",
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780),
        isMain: true
    )
    /// The display to the right of the main one.
    let side = DisplayGeom(
        key: "side",
        frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
        visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600),
        isMain: false
    )

    /// The window key with CoreGraphics id `id` in process `pid`.
    ///
    /// - Parameters:
    ///   - id: The window id.
    ///   - pid: The owning process; the default fixture process is 100.
    /// - Returns: The key.
    func window(_ id: UInt32, pid: Int32 = 100) -> WindowKey {
        WindowKey(pid: pid, launchedAt: launch, cgWindowId: id)
    }

    /// A binding with no chord that runs `action`.
    ///
    /// - Parameters:
    ///   - action: The action.
    ///   - workspace: The target workspace, for the workspace actions.
    ///   - step: The resize step, for the resize actions.
    /// - Returns: The binding.
    func binding(_ action: HotkeyAction, _ workspace: String? = nil, step: Double? = nil) -> HotkeyBinding {
        HotkeyBinding(keyCode: 0, modifiers: 0, action: action, workspaceCode: workspace, resizeStep: step)
    }

    /// An enabled state with the given windows in workspaces 1, 2 and 3; 1 and 3 are shown.
    ///
    /// - Parameters:
    ///   - one: The columns of workspace 1.
    ///   - two: The columns of workspace 2.
    ///   - three: The columns of workspace 3.
    /// - Returns: The state after `displaysChanged` and `enable`.
    func enabled(one: [StripColumn], two: [StripColumn] = [], three: [StripColumn] = []) -> WMState {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([main, side]))
        let strips = [
            WorkspaceStrip(code: "1", displayKey: "main", columns: one),
            WorkspaceStrip(code: "2", displayKey: "main", columns: two),
            WorkspaceStrip(code: "3", displayKey: "side", columns: three),
        ]
        _ = WMReducer.reduce(&state, .enable(strips: strips, active: ["main": "1", "side": "3"]))
        return state
    }

    /// The columns for window ids of the fixture process, with weight 1 each.
    ///
    /// - Parameter ids: The window ids, left to right.
    /// - Returns: The columns.
    func columns(_ ids: UInt32...) -> [StripColumn] {
        ids.map { StripColumn(window: window($0), weight: 1) }
    }

    /// An observation of window `id` of the fixture process.
    ///
    /// - Parameters:
    ///   - id: The window id.
    ///   - frame: The observed frame.
    ///   - minimized: The observed `AXMinimized` value.
    ///   - classification: The observed verdict.
    /// - Returns: The observation.
    func observed(
        _ id: UInt32,
        _ frame: CGRect = CGRect(x: 0, y: 0, width: 500, height: 780),
        minimized: Bool = false,
        classification: WindowClass = .tiled
    ) -> ObservedWindow {
        ObservedWindow(
            key: window(id),
            frame: frame,
            classification: classification,
            title: nil,
            isMinimized: minimized
        )
    }

    /// The frame effects in `effects`, keyed by window.
    ///
    /// - Parameter effects: Reducer output.
    /// - Returns: The requested frame per window.
    func frames(_ effects: [WMEffect]) -> [WindowKey: CGRect] {
        var result: [WindowKey: CGRect] = [:]
        for effect in effects {
            switch effect {
            case let .setFrame(key, frame), let .park(key, frame), let .unpark(key, frame): result[key] = frame
            default: break
            }
        }
        return result
    }

    /// True when `effects` parks `key`.
    ///
    /// - Parameters:
    ///   - effects: Reducer output.
    ///   - key: The window.
    /// - Returns: Whether a `park` for `key` is present.
    func parks(_ effects: [WMEffect], _ key: WindowKey) -> Bool {
        effects.contains { if case .park(key, _) = $0 { true } else { false } }
    }

    /// The raised windows in `effects`, in order.
    ///
    /// - Parameter effects: Reducer output.
    /// - Returns: One window per `raise`.
    func raises(_ effects: [WMEffect]) -> [WindowKey] {
        effects.compactMap { if case let .raise(key) = $0 { key } else { nil } }
    }
}
