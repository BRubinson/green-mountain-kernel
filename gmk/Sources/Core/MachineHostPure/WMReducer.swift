import CoreGraphics
import Foundation

/// The whole window-manager behaviour as one pure function from state and event to effects.
///
/// Workspaces are emulated by parking: every window of a hidden workspace hangs off a display corner. Each
/// connected display shows one of the strips placed on it; a strip whose display is gone stays hidden. Every
/// frame effect records the frame it asked for, so the notifications the shell reports back for it are
/// recognised as echoes and dropped. Effects are coalesced: one frame effect per window, then one trailing
/// `mirrorDirty` covering every window whose frame or structure changed.
enum WMReducer {
    /// The difference, in points, under which an observed frame is the echo of a requested one.
    static let echoTolerance: CGFloat = 2

    /// The resize step, in points, of the resize chords and of a resize binding that carries none.
    static let resizeStep: CGFloat = 50

    /// Folds `event` into `state` and returns the effects the shell must carry out, in order.
    ///
    /// While disabled, only `enable`, `disable`, `displaysChanged`, the mouse button, `rulesReplaced` and the
    /// bundle id of `appLaunched` change anything.
    /// While the button is held no visible strip is laid out, except by a hotkey; the release lays out, once,
    /// every strip, display change and configuration edit that arrived meanwhile. A frame of the dragged
    /// window returns only the neighbours a live reorder displaced, with no `mirrorDirty`: the release marks
    /// the strip.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - event: The event to apply.
    /// - Returns: The coalesced effects.
    static func reduce(_ state: inout WMState, _ event: WMEvent) -> [WMEffect] {
        let effects = dispatch(&state, event)
        let framed: WindowKey? =
            switch event {
            case let .windowMoved(key, _), let .windowResized(key, _): key
            default: nil
            }
        guard let framed, state.mouseDrag?.window == framed else { return coalesce(effects) }
        return effects
    }

    /// The raw effects of `event`, routed to its handler.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - event: The event to apply.
    /// - Returns: The effects before coalescing.
    private static func dispatch(_ state: inout WMState, _ event: WMEvent) -> [WMEffect] {
        switch event {
        case let .enable(strips, active): return enable(&state, strips: strips, active: active)
        case .disable: return disable(&state)
        case let .displaysChanged(displays): return displaysChanged(&state, displays)
        case let .mousePressed(point):
            state.mouseHeld = true
            state.pressPoint = point
            state.mouseDrag = nil
            return []
        case .mouseReleased: return mouseReleased(&state)
        case let .rulesReplaced(rules): return rulesReplaced(&state, rules)
        case let .appLaunched(pid, _, bundleId): if let bundleId { state.bundleIds[pid] = bundleId }
        default: break
        }
        guard state.enabled else { return [] }
        return dispatchEnabled(&state, event)
    }

    /// The raw effects of an event that acts only while management is on.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - event: The event to apply.
    /// - Returns: The effects before coalescing.
    private static func dispatchEnabled(_ state: inout WMState, _ event: WMEvent) -> [WMEffect] {
        switch event {
        case let .configure(strips, active):
            let configuration = WMConfiguration(strips: strips, active: active)
            guard !state.mouseHeld else {
                state.configurationPendingRelease = configuration
                return []
            }
            return configure(&state, configuration)
        case let .hotkey(binding): return withFreezeLifted(&state) { hotkey(&$0, binding) }
        case let .appLaunched(pid, _, _): return [.mirrorDirty(windows: [], processes: [pid], urgent: false)]
        case let .appTerminated(pid): return appTerminated(&state, pid)
        case let .windowCreated(key, frame, classification, title, isMinimized):
            let stash: StashReason? = isMinimized ? .minimized : nil
            return windowCreated(&state, key, frame: frame, classification: classification, title: title, stash: stash)
        case let .windowDestroyed(key): return windowDestroyed(&state, key)
        case let .windowFocused(key): return windowFocused(&state, key)
        case .focusUnmanaged:
            state.focused = nil
            state.focusUnmanaged = true
            return []
        case let .windowMoved(key, frame): return windowMoved(&state, key, frame)
        case let .windowResized(key, frame): return windowResized(&state, key, frame)
        case let .windowMinimized(key): return stash(&state, key, .minimized)
        case let .windowDeminimized(key, frame, classification):
            guard state.stashed[key]?.reason == .minimized else { return [] }
            return restore(&state, key, classification: classification, frame: frame, reveal: true)
        case let .appHidden(pid): return appHidden(&state, pid)
        case let .appUnhidden(pid): return appUnhidden(&state, pid, verdicts: [:])
        case .wake: return reassert(&state)
        case let .reconcile(observed, answered, hidden, unreadable):
            return reconcile(&state, observed, answered: answered, hidden: hidden, unreadable: unreadable)
        case .enable, .disable, .displaysChanged, .mousePressed, .mouseReleased, .rulesReplaced: return []
        }
    }

    /// Runs `body` as if the button were up, so a keyboard action lays out while the mouse is held.
    ///
    /// The dragged window is still skipped by every layout `body` makes.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - body: The action to run.
    /// - Returns: The effects of `body`.
    private static func withFreezeLifted(
        _ state: inout WMState,
        _ body: (inout WMState) -> [WMEffect]
    ) -> [WMEffect] {
        let held = state.mouseHeld
        state.mouseHeld = false
        defer { state.mouseHeld = held }
        return body(&state)
    }
}

// MARK: - Lifecycle

extension WMReducer {
    /// Turns management on: registers the hotkey table, shows each display's workspace, parks the rest.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - strips: Every workspace, in configuration order.
    ///   - active: The visible workspace code per display key.
    /// - Returns: The effects.
    private static func enable(
        _ state: inout WMState,
        strips: [WorkspaceStrip],
        active: [String: String]
    ) -> [WMEffect] {
        state.enabled = true
        state.workspaces = Dictionary(strips.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        state.workspaceOrder = strips.map(\.code)
            .reduce(into: []) { order, code in
                if !order.contains(code) { order.append(code) }
            }
        state.activeByDisplay = active
        state.parked = [:]
        state.expectedFrames = [:]
        state.floating = []
        state.floatWorkspace = [:]
        state.stashed = [:]
        state.classes = [:]
        state.focusUnmanaged = false
        state.mouseDrag = nil
        return [.registerHotkeys(KeyCodeTable.bindings)] + normalizeAssignments(&state) + reassert(&state)
    }

    /// Turns management off: returns every parked window to its pre-park frame and drops the hotkeys.
    ///
    /// - Parameter state: The state to update.
    /// - Returns: The effects.
    private static func disable(_ state: inout WMState) -> [WMEffect] {
        let parked = state.parked
        var effects: [WMEffect] = parked.map { .unpark($0.key, $0.value) }
        effects.append(.unregisterAllHotkeys)
        effects.append(.mirrorDirty(windows: Set(parked.keys), processes: [], urgent: true))
        for (key, frame) in parked { state.frames[key] = frame }
        state.parked = [:]
        state.expectedFrames = [:]
        state.mouseDrag = nil
        state.relayoutOnRelease = []
        state.displaysPendingRelease = false
        state.configurationPendingRelease = nil
        state.enabled = false
        return effects
    }

    /// Records the new display arrangement and, while enabled, re-picks visible strips and re-lays out.
    ///
    /// A strip placed on a display that vanished stays hidden until a configuration places it again. While
    /// the button is held the re-pick and layout wait for the release.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - displays: Every connected display.
    /// - Returns: The effects.
    private static func displaysChanged(_ state: inout WMState, _ displays: [DisplayGeom]) -> [WMEffect] {
        state.displays = displays
        guard state.enabled else { return [] }
        guard !state.mouseHeld else {
            state.displaysPendingRelease = true
            return []
        }
        return normalizeAssignments(&state) + reassert(&state)
    }

    /// Applies an edited configuration without the disable and enable round trip.
    ///
    /// Strips keep the columns the reducer holds and move to their newly placed displays; a workspace absent
    /// from the configuration hands its windows to the visible strip of its display. The configured visible
    /// code replaces the shown one on every display it names, so a workstation switch swaps what is shown.
    /// Only windows whose frame or park state changes get a frame effect, the hotkeys stay registered, and
    /// floating windows are untouched.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - configuration: Every workspace in configuration order, and the visible workspace code per display
    ///     key.
    /// - Returns: The effects.
    private static func configure(_ state: inout WMState, _ configuration: WMConfiguration) -> [WMEffect] {
        let framesBefore = state.frames
        let parkedBefore = Set(state.parked.keys)
        let orphans = replaceStrips(&state, configuration.strips)
        state.activeByDisplay.merge(configuration.active) { _, configured in configured }
        state.activeByDisplay = state.activeByDisplay.filter { state.workspaces[$0.value] != nil }
        let effects = normalizeAssignments(&state)
        rebindOrphanFloats(&state)
        for (key, displayKey) in orphans {
            let fallback = state.mainDisplay.flatMap { state.activeByDisplay[$0.key] }
            guard let target = state.activeByDisplay[displayKey] ?? fallback else { continue }
            appendColumn(&state, key, to: target)
        }
        let moves = reassert(&state)
            .filter { effect in
                switch effect {
                case let .setFrame(key, rect): return !MirrorProjection.framesMatch(framesBefore[key], rect)
                case let .park(key, rect):
                    return !parkedBefore.contains(key) || !MirrorProjection.framesMatch(framesBefore[key], rect)
                default: return true
                }
            }
        let tiled = Set(state.workspaces.values.flatMap { $0.columns.map(\.window) })
        return effects + moves + [.mirrorDirty(windows: tiled, processes: [], urgent: false)]
    }

    /// Binds every floating window whose workspace is not configured to the visible strip under it.
    ///
    /// - Parameter state: The state to update.
    private static func rebindOrphanFloats(_ state: inout WMState) {
        for key in ordered(state.floatWorkspace.keys) {
            guard let code = state.floatWorkspace[key], state.workspaces[code] == nil else { continue }
            let rebound = (state.parked[key] ?? state.frames[key]).flatMap { stripUnder(state, $0) }
            state.floatWorkspace[key] = rebound
        }
    }

    /// Replaces the configured strips with `strips`, keeping the columns the reducer holds.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - strips: Every workspace, in configuration order.
    /// - Returns: The windows of workspaces absent from `strips`, each with the display its strip was on.
    private static func replaceStrips(_ state: inout WMState, _ strips: [WorkspaceStrip]) -> [(WindowKey, String)] {
        let incoming = Set(strips.map(\.code))
        var orphans: [(WindowKey, String)] = []
        for code in state.workspaceOrder {
            guard let strip = state.workspaces[code], !incoming.contains(code) else { continue }
            orphans += strip.columns.map { ($0.window, strip.displayKey) }
            state.workspaces[code] = nil
        }
        var order: [String] = []
        for strip in strips where !order.contains(strip.code) {
            let held = state.workspaces[strip.code]
            state.workspaces[strip.code] = WorkspaceStrip(
                code: strip.code,
                displayKey: strip.displayKey,
                columns: held?.columns ?? strip.columns,
                focusedIndex: held?.focusedIndex ?? strip.focusedIndex
            )
            order.append(strip.code)
        }
        state.workspaceOrder = order
        return orphans
    }

    /// Drops stale visible-workspace entries and gives each connected display with none its first strip.
    ///
    /// An entry is stale when its display is disconnected or its strip is placed elsewhere. A display left
    /// with no visible workspace shows the first strip placed on it in configuration order; a display with
    /// no strip placed on it shows nothing. With no display connected nothing changes, so a transient empty
    /// arrangement never rewrites the visible workspaces.
    ///
    /// - Parameter state: The state to update.
    /// - Returns: A `persistActiveWorkspace` for each newly chosen workspace.
    private static func normalizeAssignments(_ state: inout WMState) -> [WMEffect] {
        guard !state.displays.isEmpty else { return [] }
        let connected = Set(state.displays.map(\.key))
        state.activeByDisplay = state.activeByDisplay.filter { displayKey, code in
            connected.contains(displayKey) && state.workspaces[code]?.displayKey == displayKey
        }
        var effects: [WMEffect] = []
        for display in state.displays where state.activeByDisplay[display.key] == nil {
            guard let code = state.workspaceOrder.first(where: { state.workspaces[$0]?.displayKey == display.key })
            else { continue }
            state.activeByDisplay[display.key] = code
            effects.append(.persistActiveWorkspace(displayKey: display.key, workspaceCode: code))
        }
        return effects
    }

    /// Lays out every visible strip and parks every hidden one at its display's current park corner.
    ///
    /// While the button is held the visible strips wait for the release and hidden ones stay where they are.
    ///
    /// - Parameter state: The state to update.
    /// - Returns: The frame effects.
    private static func reassert(_ state: inout WMState) -> [WMEffect] {
        var effects: [WMEffect] = []
        for code in state.workspaceOrder {
            if state.isActive(code) {
                effects += layout(&state, code)
            } else if !state.mouseHeld {
                effects += park(&state, code)
            }
        }
        return effects
    }
}

// MARK: - Hotkeys

extension WMReducer {
    /// Runs the action a hotkey is bound to.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - binding: The binding that fired.
    /// - Returns: The effects.
    private static func hotkey(_ state: inout WMState, _ binding: HotkeyBinding) -> [WMEffect] {
        let step = binding.resizeStep.map { CGFloat($0) } ?? resizeStep
        switch binding.action {
        case .focusWorkspace: return binding.workspaceCode.map { focusWorkspace(&state, $0) } ?? []
        case .moveToWorkspace: return binding.workspaceCode.map { moveFocused(&state, to: $0) } ?? []
        case .focusLeft: return focusStep(&state, -1)
        case .focusRight: return focusStep(&state, 1)
        case .slideLeft: return slide(&state, -1)
        case .slideRight: return slide(&state, 1)
        case .resizeGrow: return resize(&state, step)
        case .resizeShrink: return resize(&state, -step)
        }
    }

    /// Shows workspace `code` on its display, parking the one it replaces, and focuses its window.
    ///
    /// A code placed on another display is shown there, never pulled across; a code whose display is
    /// disconnected does nothing.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The workspace to show.
    /// - Returns: The effects; none while the button is held.
    private static func focusWorkspace(_ state: inout WMState, _ code: String) -> [WMEffect] {
        guard !state.mouseHeld, let strip = state.workspaces[code], state.display(forKey: strip.displayKey) != nil
        else { return [] }
        let displayKey = strip.displayKey
        var effects: [WMEffect] = []
        if state.activeByDisplay[displayKey] != code {
            if let previous = state.activeByDisplay[displayKey] { effects += park(&state, previous) }
            state.activeByDisplay[displayKey] = code
            effects += layout(&state, code)
            effects.append(.persistActiveWorkspace(displayKey: displayKey, workspaceCode: code))
            effects.append(.mirrorDirty(windows: [], processes: [], urgent: true))
        }
        return effects + focusStrip(&state, code)
    }

    /// Moves the focused window to the end of workspace `target`, parking it when that workspace is hidden.
    ///
    /// With no focused window, the current strip's focused column, else its first column, is moved. A
    /// focused floating window is carried to the target workspace instead. Focus then lands on the source
    /// strip's left neighbour of the moved column.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - target: The destination workspace.
    /// - Returns: The effects.
    private static func moveFocused(_ state: inout WMState, to target: String) -> [WMEffect] {
        if let key = state.focused, state.floating.contains(key) { return moveFloat(&state, key, to: target) }
        guard let key = moveCandidate(state), let source = state.stripCode(containing: key), source != target,
            let destination = state.workspaces[target]
        else { return [] }
        var effects = removeColumn(&state, key, from: source)
        appendColumn(&state, key, to: target)
        if state.isActive(target) {
            effects += layout(&state, target)
        } else if let display = state.display(forKey: destination.displayKey) {
            let corner = ParkGeometry.parkCorner(for: display, among: state.displays)
            effects.append(parkWindow(&state, key, display: display, corner: corner))
        }
        state.focused = nil
        effects.append(.mirrorDirty(windows: [key], processes: [], urgent: false))
        return effects + focusStrip(&state, source)
    }

    /// The window a move acts on: the focused tiled window, else the current strip's focused column.
    ///
    /// - Parameter state: The current state.
    /// - Returns: The window, or nil when focus is unmanaged, a floating window holds it, or no strip has a
    ///   column.
    private static func moveCandidate(_ state: WMState) -> WindowKey? {
        guard !state.focusUnmanaged else { return nil }
        if let focused = state.focused { return state.stripCode(containing: focused) == nil ? nil : focused }
        guard let code = state.currentStripCode, let strip = state.workspaces[code], let first = strip.columns.first
        else { return nil }
        guard let index = strip.focusedIndex, strip.columns.indices.contains(index) else { return first.window }
        return strip.columns[index].window
    }

    /// Moves focus `delta` columns within the current strip, stopping at either end.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - delta: Columns to move; negative is left.
    /// - Returns: The focus effect, or none at an end.
    private static func focusStep(_ state: inout WMState, _ delta: Int) -> [WMEffect] {
        guard let code = state.currentStripCode, let strip = state.workspaces[code],
            let index = ColumnLayout.focusIndex(from: strip.focusedIndex, delta: delta, count: strip.columns.count),
            index != strip.focusedIndex || state.focused != strip.columns[index].window
        else { return [] }
        state.workspaces[code]?.focusedIndex = index
        return focusStrip(&state, code)
    }

    /// Swaps the focused column with its neighbour `delta` places away; weights travel with their windows.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - delta: Places to move; negative is left.
    /// - Returns: The effects, or none at an end.
    private static func slide(_ state: inout WMState, _ delta: Int) -> [WMEffect] {
        guard let code = state.currentStripCode, let strip = state.workspaces[code],
            let index = strip.focusedIndex
        else { return [] }
        let (columns, newIndex) = ColumnLayout.slide(order: strip.columns, index: index, delta: delta)
        guard newIndex != index else { return [] }
        state.workspaces[code]?.columns = columns
        state.workspaces[code]?.focusedIndex = newIndex
        let moved: Set<WindowKey> = [columns[index].window, columns[newIndex].window]
        let relayout = state.isActive(code) ? layout(&state, code) : []
        return relayout + [.mirrorDirty(windows: moved, processes: [], urgent: false)]
    }

    /// Widens the focused column by `delta` points, taking the width from a neighbour.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - delta: Points to add; negative narrows.
    /// - Returns: The effects.
    private static func resize(_ state: inout WMState, _ delta: CGFloat) -> [WMEffect] {
        guard let code = state.currentStripCode, let strip = state.workspaces[code],
            let index = strip.focusedIndex, let display = state.display(forKey: strip.displayKey)
        else { return [] }
        let weights = ColumnLayout.resizeStep(
            weights: strip.weights,
            index: index,
            deltaPoints: delta,
            visibleWidth: display.visibleFrame.width
        )
        return applyWeights(&state, code, weights)
    }
}

// MARK: - Window events

extension WMReducer {
    /// Tiles a new window at the end of the visible strip under it, floats it, or stashes it.
    ///
    /// The app's rule decides ahead of the classification. A popup is never tracked. A window that arrives
    /// stashed records only the workspace under it, not its verdict, and is classified on its return. While
    /// the button is held an unknown window is left unadopted; the first reconcile after the release adopts it.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The new window.
    ///   - frame: Its frame.
    ///   - classification: The heuristic verdict.
    ///   - title: Its title, when it reports one.
    ///   - stash: Why the window arrives out of the layout, or nil when it arrives on screen.
    /// - Returns: The effects.
    private static func windowCreated(
        _ state: inout WMState,
        _ key: WindowKey,
        frame: CGRect,
        classification: WindowClass,
        title: String?,
        stash: StashReason?
    ) -> [WMEffect] {
        if classification == .popup, !state.knows(key) { return [] }
        state.frames[key] = frame
        if let title { state.titles[key] = title }
        guard !state.knows(key), !state.mouseHeld else { return [] }
        let dirty: [WMEffect] = [.mirrorDirty(windows: [key], processes: [], urgent: false)]
        if let stash {
            let code = stripUnder(state, frame)
            state.stashed[key] = StashedWindow(reason: stash, workspaceCode: code, kind: nil, index: nil, weight: nil)
            return dirty
        }
        state.classes[key] = classification
        let kind = state.ruleKind(for: key) ?? classification
        guard kind == .tiled, let code = stripUnder(state, frame), state.workspaces[code] != nil else {
            state.floating.insert(key)
            state.floatWorkspace[key] = stripUnder(state, frame)
            return dirty
        }
        appendColumn(&state, key, to: code)
        return layout(&state, code) + dirty
    }

    /// Forgets a closed window and closes the gap it leaves.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The closed window.
    /// - Returns: The effects.
    private static func windowDestroyed(_ state: inout WMState, _ key: WindowKey) -> [WMEffect] {
        var effects: [WMEffect] = []
        if let code = state.stripCode(containing: key) { effects += removeColumn(&state, key, from: code) }
        state.floating.remove(key)
        state.parked[key] = nil
        state.expectedFrames[key] = nil
        state.frames[key] = nil
        state.titles[key] = nil
        state.classes[key] = nil
        state.floatWorkspace[key] = nil
        state.stashed[key] = nil
        if state.focused == key { state.focused = nil }
        if state.mouseDrag?.window == key { state.mouseDrag = nil }
        return effects + [.mirrorDirty(windows: [key], processes: [], urgent: false)]
    }

    /// Tracks focus; focusing a window of a hidden workspace shows that workspace.
    ///
    /// Focus on a window that is neither tiled nor floating is unmanaged, so a move does nothing until a
    /// managed window takes focus. While the button is held focus is only recorded, and a window of a hidden
    /// workspace is ignored: a click-activation can report a stale focused window, and showing its workspace
    /// would move the strip under the pointer.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The focused window.
    /// - Returns: The effects of showing its workspace, if it was hidden.
    private static func windowFocused(_ state: inout WMState, _ key: WindowKey) -> [WMEffect] {
        if state.floating.contains(key) {
            state.focused = key
            state.focusUnmanaged = false
            return []
        }
        guard let code = state.stripCode(containing: key) else {
            state.focused = nil
            state.focusUnmanaged = true
            return []
        }
        state.focusUnmanaged = false
        if state.mouseHeld, !state.isActive(code) { return [] }
        let index = state.workspaces[code]?.columns.firstIndex { $0.window == key }
        state.workspaces[code]?.focusedIndex = index
        let effects = state.isActive(code) ? [] : focusWorkspace(&state, code)
        state.focused = key
        state.focusedWorkspace = code
        return effects
    }

    /// Records a user move of a window; echoes are ignored and the moved window's frame is never written.
    ///
    /// With the button held, a move of the visible tiled window under the press starts or continues its mouse
    /// drag; any other visible tiled window that moved is re-laid out on release. A floating window moved
    /// with the button up joins the visible workspace under it.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The moved window.
    ///   - frame: Its new frame.
    /// - Returns: A `mirrorDirty` for a floating window, the live reorder of a drag, else nothing.
    private static func windowMoved(_ state: inout WMState, _ key: WindowKey, _ frame: CGRect) -> [WMEffect] {
        if state.mouseDrag?.window == key { return dragObserved(&state, frame, resized: false) }
        if let expected = state.expectedFrames[key], MirrorProjection.framesMatch(expected, frame) { return [] }
        guard state.parked[key] == nil else { return [] }
        if state.mouseHeld, claimDrag(&state, key) { return dragObserved(&state, frame, resized: false) }
        state.frames[key] = frame
        if !state.mouseHeld, state.floating.contains(key), let code = stripUnder(state, frame) {
            state.floatWorkspace[key] = code
        }
        if state.mouseHeld, let code = state.stripCode(containing: key), state.isActive(code) {
            state.relayoutOnRelease.insert(code)
        }
        return state.floating.contains(key) ? [.mirrorDirty(windows: [key], processes: [], urgent: false)] : []
    }

    /// Records a resize; layout echoes are ignored and the dragged window's resize waits for the release.
    ///
    /// A resize of any window but the dragged one is the app clamping the frame it was given: that frame is
    /// accepted as the window's own, with no re-weight and no re-layout, so an app minimum width cannot
    /// start a loop.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The resized window.
    ///   - frame: Its new frame.
    /// - Returns: The effects.
    private static func windowResized(_ state: inout WMState, _ key: WindowKey, _ frame: CGRect) -> [WMEffect] {
        guard state.parked[key] == nil else { return [] }
        if state.mouseDrag?.window == key { return dragObserved(&state, frame, resized: true) }
        if let expected = state.expectedFrames[key], abs(expected.width - frame.width) <= echoTolerance { return [] }
        if state.mouseHeld, claimDrag(&state, key) { return dragObserved(&state, frame, resized: true) }
        state.frames[key] = frame
        let dirty: [WMEffect] = [.mirrorDirty(windows: [key], processes: [], urgent: false)]
        guard let code = state.stripCode(containing: key), state.isActive(code) else {
            return state.floating.contains(key) ? dirty : []
        }
        state.expectedFrames[key] = frame
        return dirty
    }

    /// Forgets every window of a terminated process.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - pid: The terminated process.
    /// - Returns: The effects.
    private static func appTerminated(_ state: inout WMState, _ pid: Int32) -> [WMEffect] {
        var effects: [WMEffect] = []
        for key in state.allWindows where key.pid == pid {
            effects += windowDestroyed(&state, key)
        }
        state.bundleIds[pid] = nil
        return effects + [.mirrorDirty(windows: [], processes: [pid], urgent: false)]
    }

    /// Replaces the reducer's view of which windows exist with an observation.
    ///
    /// A tracked window is destroyed only when its process answered and reported neither it nor an
    /// unreadable entry for it, so a process that timed out keeps every window, parked ones included. Hidden
    /// apps stash and return, a missed minimize or deminimize is caught up, and titles are refreshed.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - observed: Every window the answering processes report.
    ///   - answered: The pids that answered the snapshot.
    ///   - hidden: The pids whose app is hidden.
    ///   - unreadable: Windows whose id read but whose frame did not.
    /// - Returns: The effects of the implied creations, destructions, stashes and restores.
    private static func reconcile(
        _ state: inout WMState,
        _ observed: [ObservedWindow],
        answered: Set<Int32>,
        hidden: Set<Int32>,
        unreadable: Set<WindowKey>
    ) -> [WMEffect] {
        var effects: [WMEffect] = []
        let seen = Set(observed.map(\.key)).union(unreadable)
        for key in ordered(state.allWindows) where answered.contains(key.pid) && !seen.contains(key) {
            effects += windowDestroyed(&state, key)
        }
        let verdicts = Dictionary(observed.map { ($0.key, $0) }, uniquingKeysWith: { $1 })
        effects += reconcileHidden(&state, hidden, verdicts: verdicts)
        for window in observed {
            if let title = window.title { state.titles[window.key] = title }
            effects += reconcileWindow(&state, window, hidden: hidden)
        }
        return effects
    }

    /// Stashes the managed windows of every hidden app and restores the hidden stashes of every shown one.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - hidden: The pids whose app is hidden.
    ///   - verdicts: This reconcile's observation of each window, the fresh verdict a restore takes.
    /// - Returns: The effects of the stashes and restores.
    private static func reconcileHidden(
        _ state: inout WMState,
        _ hidden: Set<Int32>,
        verdicts: [WindowKey: ObservedWindow]
    ) -> [WMEffect] {
        var effects: [WMEffect] = []
        for pid in hidden.sorted() { effects += appHidden(&state, pid) }
        let shown = Set(state.stashed.filter { $0.value.reason == .hidden && !hidden.contains($0.key.pid) }.keys)
        for pid in Set(shown.map(\.pid)).sorted() { effects += appUnhidden(&state, pid, verdicts: verdicts) }
        return effects
    }

    /// Folds one observed window into the state.
    ///
    /// A minimized stash returns once the window reads unminimized and its app is shown. An unknown
    /// window is created, stashed when it is minimized or its app is hidden. A known window that reads
    /// minimized is stashed; any other is re-tested, which may promote a float but never demotes a tile.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - window: The observation.
    ///   - hidden: The pids whose app is hidden.
    /// - Returns: The effects.
    private static func reconcileWindow(
        _ state: inout WMState,
        _ window: ObservedWindow,
        hidden: Set<Int32>
    ) -> [WMEffect] {
        let key = window.key
        let appHidden = hidden.contains(key.pid)
        if let stash = state.stashed[key] {
            guard stash.reason == .minimized, !window.isMinimized, !appHidden else { return [] }
            return restore(&state, key, classification: window.classification, frame: window.frame)
        }
        guard state.knows(key) else {
            let stash: StashReason? = window.isMinimized ? .minimized : (appHidden ? .hidden : nil)
            return windowCreated(
                &state,
                key,
                frame: window.frame,
                classification: window.classification,
                title: window.title,
                stash: stash
            )
        }
        if window.isMinimized { return stash(&state, key, .minimized) }
        guard !appHidden, window.classification != .popup else { return [] }
        state.classes[key] = window.classification
        return redisposition(&state, key, heuristic: window.classification)
    }
}

// MARK: - Stash and restore

extension WMReducer {
    /// Stashes every managed window of app `pid`, rightmost column first.
    ///
    /// Stashing right to left records every column at the index it holds now, so a left-to-right restore
    /// rebuilds the strip in its order.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - pid: The hidden app.
    /// - Returns: The effects.
    private static func appHidden(_ state: inout WMState, _ pid: Int32) -> [WMEffect] {
        let snapshot = state
        let keys = state.allWindows.filter { $0.pid == pid && snapshot.stashed[$0] == nil }
            .sorted { lhs, rhs in
                (columnIndex(snapshot, lhs) ?? -1, lhs.cgWindowId) > (columnIndex(snapshot, rhs) ?? -1, rhs.cgWindowId)
            }
        var effects: [WMEffect] = []
        for key in keys { effects += stash(&state, key, .hidden) }
        return effects
    }

    /// The column index `key` holds in its strip, or nil when it is not tiled.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - key: The window.
    /// - Returns: The index, or nil.
    private static func columnIndex(_ state: WMState, _ key: WindowKey) -> Int? {
        state.stripCode(containing: key).flatMap { state.workspaces[$0]?.columns.firstIndex { $0.window == key } }
    }

    /// Restores every window of app `pid` that was stashed because the app was hidden, leftmost first.
    ///
    /// A window first seen while hidden has no placement of its own, so it stays stashed until an
    /// observation in `verdicts` classifies it.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - pid: The shown app.
    ///   - verdicts: The fresh observation of each window, empty outside a reconcile.
    /// - Returns: The effects.
    private static func appUnhidden(
        _ state: inout WMState,
        _ pid: Int32,
        verdicts: [WindowKey: ObservedWindow]
    ) -> [WMEffect] {
        let stashes = state.stashed.filter { $0.key.pid == pid && $0.value.reason == .hidden }
        let keys = stashes.keys.sorted { lhs, rhs in
            (stashes[lhs]?.index ?? .max, lhs.cgWindowId) < (stashes[rhs]?.index ?? .max, rhs.cgWindowId)
        }
        var effects: [WMEffect] = []
        for key in keys {
            guard stashes[key]?.kind == nil else {
                effects += restore(&state, key, classification: nil, frame: nil)
                continue
            }
            guard let observed = verdicts[key] else { continue }
            effects += restore(&state, key, classification: observed.classification, frame: observed.frame)
        }
        return effects
    }

    /// Takes a managed window out of the layout, remembering where it was.
    ///
    /// A tiled window closes its gap and records its workspace, index and relative weight; a floating window
    /// records its workspace. The pre-park frame is kept, so a restore into a hidden workspace re-parks from
    /// the true frame.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window.
    ///   - reason: Why it leaves the layout.
    /// - Returns: The re-layout of its strip and a `mirrorDirty`; none for an unmanaged or stashed window.
    private static func stash(_ state: inout WMState, _ key: WindowKey, _ reason: StashReason) -> [WMEffect] {
        guard state.stashed[key] == nil else { return [] }
        var effects: [WMEffect] = []
        let entry: StashedWindow
        if let code = state.stripCode(containing: key), let strip = state.workspaces[code],
            let index = strip.columns.firstIndex(where: { $0.window == key })
        {
            let others = strip.weights.enumerated().filter { $0.offset != index }.map(\.element)
            let mean = others.isEmpty ? 0 : others.reduce(0, +) / Double(others.count)
            let weight = mean > 0 ? strip.columns[index].weight / mean : 1
            entry = StashedWindow(reason: reason, workspaceCode: code, kind: .tiled, index: index, weight: weight)
            effects = removeColumn(&state, key, from: code)
        } else if state.floating.remove(key) != nil {
            let code = state.floatWorkspace.removeValue(forKey: key)
            entry = StashedWindow(reason: reason, workspaceCode: code, kind: .floating, index: nil, weight: nil)
        } else {
            return []
        }
        if state.focused == key { state.focused = nil }
        if state.mouseDrag?.window == key { state.mouseDrag = nil }
        state.expectedFrames[key] = nil
        state.stashed[key] = entry
        return effects + [.mirrorDirty(windows: [key], processes: [], urgent: false)]
    }

    /// Returns a stashed window to the layout where it was.
    ///
    /// The app's rule decides ahead of the stashed placement and the last verdict. The window returns to its
    /// workspace when that is still configured, else to the visible strip under it. A tiled window takes
    /// back its column index and relative weight; a floating window comes back out of its park and is raised.
    /// A revealed return into a hidden workspace shows that workspace with the window focused; any other
    /// return into a hidden workspace parks the window.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The stashed window.
    ///   - classification: The window's verdict on its return, or nil when unknown.
    ///   - frame: The window's frame on its return, or nil when unknown.
    ///   - reveal: True when the user brought the window back, so its workspace is shown rather than parked.
    /// - Returns: The effects; none when the window is not stashed.
    private static func restore(
        _ state: inout WMState,
        _ key: WindowKey,
        classification: WindowClass?,
        frame: CGRect?,
        reveal: Bool = false
    ) -> [WMEffect] {
        guard let stash = state.stashed.removeValue(forKey: key) else { return [] }
        if let classification, classification != .popup { state.classes[key] = classification }
        if let frame { state.frames[key] = frame }
        let kind = state.ruleKind(for: key) ?? stash.kind ?? state.classes[key] ?? .floating
        let configured = stash.workspaceCode.flatMap { state.workspaces[$0] == nil ? nil : $0 }
        let code = configured ?? (frame ?? state.frames[key]).flatMap { stripUnder(state, $0) }
        let dirty: [WMEffect] = [.mirrorDirty(windows: [key], processes: [], urgent: false)]
        if reveal, let code, !state.isActive(code), !state.mouseHeld {
            return revealInto(&state, key, code, tiled: kind == .tiled, stash: stash) + dirty
        }
        guard let code, kind == .tiled else { return restoreFloat(&state, key, to: code) + dirty }
        insertColumn(&state, key, to: code, at: stash.index, weight: stash.weight)
        let placed = state.isActive(code) ? layout(&state, code) : parkInto(&state, key, code)
        return placed + dirty
    }

    /// Returns a stashed window into hidden workspace `code` and shows that workspace.
    ///
    /// The returning window takes focus.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The returning window.
    ///   - code: The hidden workspace it belongs to.
    ///   - tiled: True to take back its column, false to return as a float bound to `code`.
    ///   - stash: Its stashed placement.
    /// - Returns: The effects of showing the workspace, then a `focus` of a returning float.
    private static func revealInto(
        _ state: inout WMState,
        _ key: WindowKey,
        _ code: String,
        tiled: Bool,
        stash: StashedWindow
    ) -> [WMEffect] {
        guard tiled else {
            state.floating.insert(key)
            state.floatWorkspace[key] = code
            let effects = focusWorkspace(&state, code)
            state.focused = key
            return effects + [.focus(key)]
        }
        insertColumn(&state, key, to: code, at: stash.index, weight: stash.weight)
        let index = state.workspaces[code]?.columns.firstIndex { $0.window == key }
        state.workspaces[code]?.focusedIndex = index
        return focusWorkspace(&state, code)
    }

    /// Returns a stashed window as a float bound to `code`, out of its park when that workspace is shown.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window.
    ///   - code: The workspace it belongs to, or nil when there is none.
    /// - Returns: An `unpark` and `raise` when shown, a `park` when hidden, else nothing.
    private static func restoreFloat(_ state: inout WMState, _ key: WindowKey, to code: String?) -> [WMEffect] {
        state.floating.insert(key)
        guard let code else { return [] }
        state.floatWorkspace[key] = code
        guard state.isActive(code) else { return parkInto(&state, key, code) }
        guard let prePark = state.parked.removeValue(forKey: key) else { return [] }
        state.frames[key] = prePark
        state.expectedFrames[key] = prePark
        return [.unpark(key, prePark), .raise(key)]
    }

    /// Inserts `key` as a column of strip `code`, clamping the index and restoring its relative weight.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window to tile.
    ///   - code: The strip.
    ///   - index: The column index it held, or nil to append.
    ///   - weight: Its weight relative to the mean of the other columns, or nil for the mean.
    private static func insertColumn(
        _ state: inout WMState,
        _ key: WindowKey,
        to code: String,
        at index: Int?,
        weight: Double?
    ) {
        guard var strip = state.workspaces[code] else { return }
        let position = min(max(index ?? strip.columns.count, 0), strip.columns.count)
        var weights = strip.weights
        let mean = ColumnLayout.appendWeight(existing: weights)
        weights.insert((weight ?? 1) * mean, at: position)
        weights = ColumnLayout.renormalize(weights)
        strip.columns.insert(StripColumn(window: key, weight: 0), at: position)
        for column in strip.columns.indices { strip.columns[column].weight = weights[column] }
        if let focused = strip.focusedIndex {
            strip.focusedIndex = focused >= position ? focused + 1 : focused
        } else {
            strip.focusedIndex = 0
        }
        state.workspaces[code] = strip
    }

    /// Parks `key` at the park corner of the display that strip `code` is placed on.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window to hide.
    ///   - code: The hidden strip it belongs to.
    /// - Returns: The `park` effect, or none when the strip or its display is missing.
    private static func parkInto(_ state: inout WMState, _ key: WindowKey, _ code: String) -> [WMEffect] {
        guard let strip = state.workspaces[code], let display = state.display(forKey: strip.displayKey) else {
            return []
        }
        let corner = ParkGeometry.parkCorner(for: display, among: state.displays)
        return [parkWindow(&state, key, display: display, corner: corner)]
    }
}

// MARK: - Rules and floats

extension WMReducer {
    /// Replaces the per-app rules and re-places every managed window of an app whose rule changed.
    ///
    /// Stashed windows are untouched; their restore consults the rule.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - rules: Every rule, keyed by bundle id.
    /// - Returns: The effects; none while disabled.
    private static func rulesReplaced(_ state: inout WMState, _ rules: [String: WindowClass]) -> [WMEffect] {
        let changed = Set(rules.keys).union(state.rules.keys).filter { rules[$0] != state.rules[$0] }
        state.rules = rules
        guard state.enabled else { return [] }
        var effects: [WMEffect] = []
        for key in ordered(state.allWindows) where state.stashed[key] == nil {
            guard let bundleId = state.bundleIds[key.pid], changed.contains(bundleId) else { continue }
            let heuristic = state.classes[key] ?? (state.floating.contains(key) ? .floating : .tiled)
            effects += redisposition(&state, key, heuristic: heuristic, allowDemote: true)
        }
        return effects
    }

    /// Tiles or floats a managed window as its app's rule, else the heuristic, now asks.
    ///
    /// A tile is floated only by a rule or when `allowDemote` is set, never on the heuristic alone, since a
    /// fullscreen button can flicker during a tab drag.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window.
    ///   - heuristic: The window's heuristic verdict.
    ///   - allowDemote: True to let the heuristic float a tiled window.
    /// - Returns: The effects; none when the placement stands.
    private static func redisposition(
        _ state: inout WMState,
        _ key: WindowKey,
        heuristic: WindowClass,
        allowDemote: Bool = false
    ) -> [WMEffect] {
        let rule = state.ruleKind(for: key)
        let want = rule ?? heuristic
        if want == .tiled, state.floating.contains(key) { return tile(&state, key) }
        if want == .floating, state.stripCode(containing: key) != nil, rule != nil || allowDemote {
            return float(&state, key)
        }
        return []
    }

    /// Moves a floating window into a column at the end of its workspace.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The floating window.
    /// - Returns: The layout or park of the window; none when no workspace can take it.
    private static func tile(_ state: inout WMState, _ key: WindowKey) -> [WMEffect] {
        let bound = state.floatWorkspace[key]
        let under = (state.parked[key] ?? state.frames[key]).flatMap { stripUnder(state, $0) }
        guard let code = bound.flatMap({ state.workspaces[$0] == nil ? nil : $0 }) ?? under,
            state.workspaces[code] != nil
        else { return [] }
        state.floating.remove(key)
        state.floatWorkspace[key] = nil
        appendColumn(&state, key, to: code)
        let placed = state.isActive(code) ? layout(&state, code) : parkInto(&state, key, code)
        return placed + [.mirrorDirty(windows: [key], processes: [], urgent: false)]
    }

    /// Takes a tiled window out of its strip and floats it, bound to that workspace.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The tiled window.
    /// - Returns: The strip's re-layout and a `raise` when it is shown.
    private static func float(_ state: inout WMState, _ key: WindowKey) -> [WMEffect] {
        guard let code = state.stripCode(containing: key) else { return [] }
        var effects = removeColumn(&state, key, from: code)
        state.floating.insert(key)
        state.floatWorkspace[key] = code
        state.expectedFrames[key] = nil
        if state.isActive(code) { effects.append(.raise(key)) }
        return effects + [.mirrorDirty(windows: [key], processes: [], urgent: false)]
    }

    /// Carries a focused floating window to workspace `target`, keeping its place on the display.
    ///
    /// The frame keeps its offset from the visible origin and is clamped inside the target display. A
    /// hidden target parks the window; focus then lands on the source strip.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The floating window.
    ///   - target: The destination workspace.
    /// - Returns: The effects; none when the target is its workspace, missing or off a connected display.
    private static func moveFloat(_ state: inout WMState, _ key: WindowKey, to target: String) -> [WMEffect] {
        let source = state.floatWorkspace[key]
        guard source != target, let strip = state.workspaces[target],
            let display = state.display(forKey: strip.displayKey)
        else { return [] }
        let from = source.flatMap { state.workspaces[$0] }.flatMap { state.display(forKey: $0.displayKey) }
        let frame = state.parked[key] ?? state.frames[key] ?? display.visibleFrame
        let carried = carry(frame, from: from?.visibleFrame ?? display.visibleFrame, to: display.visibleFrame)
        let wasParked = state.parked.removeValue(forKey: key) != nil
        state.floatWorkspace[key] = target
        state.frames[key] = carried
        var effects: [WMEffect]
        if state.isActive(target) {
            state.expectedFrames[key] = carried
            effects = [wasParked ? .unpark(key, carried) : .setFrame(key, carried), .raise(key)]
        } else {
            effects = parkInto(&state, key, target)
        }
        state.focused = nil
        effects.append(.mirrorDirty(windows: [key], processes: [], urgent: false))
        return effects + (source.map { focusStrip(&state, $0) } ?? [])
    }

    /// The frame `frame` moved from one visible area to another at the same offset, clamped inside it.
    ///
    /// - Parameters:
    ///   - frame: The window's frame.
    ///   - source: The visible frame it sits in.
    ///   - target: The visible frame it moves to.
    /// - Returns: The carried frame, no larger than `target` and wholly inside it.
    private static func carry(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let width = min(frame.width, target.width)
        let height = min(frame.height, target.height)
        let x = min(max(target.minX + frame.minX - source.minX, target.minX), target.maxX - width)
        let y = min(max(target.minY + frame.minY - source.minY, target.minY), target.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Binds every shown floating window whose centre sits on another display to that display's workspace.
    ///
    /// - Parameter state: The state to update.
    /// - Returns: A `mirrorDirty` for the rebound windows, or none.
    private static func rebindFloats(_ state: inout WMState) -> [WMEffect] {
        var rebound: Set<WindowKey> = []
        for key in ordered(state.floating) where state.parked[key] == nil {
            guard let frame = state.frames[key] else { continue }
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            guard let display = state.displays.first(where: { $0.frame.contains(centre) }),
                let code = state.activeByDisplay[display.key]
            else { continue }
            let bound = state.floatWorkspace[key].flatMap { state.workspaces[$0]?.displayKey }
            guard bound != display.key else { continue }
            state.floatWorkspace[key] = code
            rebound.insert(key)
        }
        return rebound.isEmpty ? [] : [.mirrorDirty(windows: rebound, processes: [], urgent: false)]
    }

    /// The `raise` of every shown, unfocused float bound to workspace `code`.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - code: The workspace.
    /// - Returns: One `raise` per float, ordered by pid then window id.
    private static func raiseFloats(_ state: WMState, _ code: String) -> [WMEffect] {
        state.floats(boundTo: code).filter { state.parked[$0] == nil && $0 != state.focused }.map { .raise($0) }
    }

    /// The windows in `keys` ordered by pid then window id, so iteration never depends on hashing.
    ///
    /// - Parameter keys: The windows.
    /// - Returns: The ordered windows.
    private static func ordered(_ keys: some Sequence<WindowKey>) -> [WindowKey] {
        keys.sorted { ($0.pid, $0.cgWindowId) < ($1.pid, $1.cgWindowId) }
    }
}

// MARK: - Mouse drags

extension WMReducer {
    /// The midpoint travel, in points, at a constant width that decides a drag is a move.
    static let moveThreshold: CGFloat = 8

    /// Makes `key` the dragged window when no drag is under way and it is the visible tiled window pressed.
    ///
    /// The window whose slot holds the press point claims the drag, so a neighbour's echo never can; with no
    /// press point the focused window, or with none focused the first to move, claims it. The drag starts
    /// from where the reducer last placed the window, else from its layout slot.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window the held button moved or resized.
    /// - Returns: True when `key` is the dragged window, whether claimed now or earlier.
    private static func claimDrag(_ state: inout WMState, _ key: WindowKey) -> Bool {
        if let drag = state.mouseDrag { return drag.window == key }
        guard let code = state.stripCode(containing: key), state.isActive(code),
            let slot = slot(state, key, in: code)
        else { return false }
        if let press = state.pressPoint {
            guard slot.contains(press) else { return false }
        } else {
            guard state.focused == nil || state.focused == key else { return false }
        }
        let start = state.expectedFrames[key] ?? slot
        let origin = state.frames[key] ?? start
        state.mouseDrag = MouseDrag(
            window: key,
            startFrame: start,
            originFrame: origin,
            slotOriginX: origin.minX,
            latestFrame: origin
        )
        return true
    }

    /// Records the dragged window's latest frame, decides the drag's mode, and reorders a move live.
    ///
    /// The first frame fixes the drag's base width; a resize event measures from the requested width instead,
    /// since an edge drag's first report has already changed it. A width off the base locks a resize; a
    /// midpoint travel past `moveThreshold` at the base width locks a move.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - frame: The dragged window's new frame.
    ///   - resized: True when the frame came with a resize event.
    /// - Returns: The neighbours a live reorder displaced; never a frame for the dragged window.
    private static func dragObserved(_ state: inout WMState, _ frame: CGRect, resized: Bool) -> [WMEffect] {
        guard var drag = state.mouseDrag else { return [] }
        state.frames[drag.window] = frame
        drag.latestFrame = frame
        let base = drag.baseWidth ?? (resized ? drag.startFrame.width : frame.width)
        drag.baseWidth = base
        if drag.mode == .undecided {
            if abs(frame.width - base) > echoTolerance {
                drag.mode = .resize
            } else if abs(frame.midX - drag.originFrame.midX) > moveThreshold {
                drag.mode = .move
            }
        }
        let effects = drag.mode == .move ? reorder(&state, &drag) : []
        state.mouseDrag = drag
        return effects
    }

    /// Swaps the dragged window past each neighbour its displacement reached, one adjacent swap at a time.
    ///
    /// Each swap moves the drag's slot origin by as far as the window's slot moved, so the next crossing
    /// is measured from the new slot. Weights travel with their windows and focus follows the dragged one.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - drag: The drag, whose slot origin and last-passed neighbour follow each swap.
    /// - Returns: One frame effect per displaced neighbour at its new slot; none for the dragged window.
    private static func reorder(_ state: inout WMState, _ drag: inout MouseDrag) -> [WMEffect] {
        let key = drag.window
        guard let code = state.stripCode(containing: key), state.isActive(code), var strip = state.workspaces[code],
            let display = state.display(forKey: strip.displayKey),
            var index = strip.columns.firstIndex(where: { $0.window == key })
        else { return [] }
        let visible = display.visibleFrame
        var slots = ColumnLayout.frames(weights: strip.weights, visible: visible)
        var displaced: [WindowKey] = []
        for _ in strip.columns.indices {
            let returning = strip.columns.firstIndex { $0.window == drag.lastPassed }
            guard
                let target = ColumnLayout.reorderTarget(
                    slots: slots,
                    index: index,
                    displacement: drag.displacement,
                    returning: returning
                )
            else { break }
            let passed = strip.columns[target].window
            strip.columns.swapAt(index, target)
            let moved = ColumnLayout.frames(weights: strip.weights, visible: visible)
            drag.slotOriginX += moved[target].minX - slots[index].minX
            drag.lastPassed = passed
            slots = moved
            if !displaced.contains(passed) { displaced.append(passed) }
            index = target
        }
        guard !displaced.isEmpty else { return [] }
        strip.focusedIndex = index
        state.workspaces[code] = strip
        return displaced.compactMap { neighbour in
            guard let position = strip.columns.firstIndex(where: { $0.window == neighbour }) else { return nil }
            let frame = slots[position]
            state.expectedFrames[neighbour] = frame
            state.frames[neighbour] = frame
            let wasParked = state.parked.removeValue(forKey: neighbour) != nil
            return wasParked ? .unpark(neighbour, frame) : .setFrame(neighbour, frame)
        }
    }

    /// Ends the mouse drag and lays out, once, everything held back while the button was down.
    ///
    /// The drag settles first and floats dragged to another display join its workspace, then a held-back
    /// configuration edit and display change apply, then every held-back strip that is still visible is laid
    /// out. The drop point plays no part.
    ///
    /// - Parameter state: The state to update.
    /// - Returns: The effects, or none when nothing was held back.
    private static func mouseReleased(_ state: inout WMState) -> [WMEffect] {
        state.mouseHeld = false
        state.pressPoint = nil
        let drag = state.mouseDrag
        state.mouseDrag = nil
        guard state.enabled else { return [] }
        var effects = drag.map { settle(&state, $0) } ?? []
        effects += rebindFloats(&state)
        if let configuration = state.configurationPendingRelease {
            state.configurationPendingRelease = nil
            effects += configure(&state, configuration)
        }
        if state.displaysPendingRelease {
            state.displaysPendingRelease = false
            effects += normalizeAssignments(&state) + reassert(&state)
        }
        let pending = state.relayoutOnRelease
        state.relayoutOnRelease = []
        for code in state.workspaceOrder where pending.contains(code) && state.isActive(code) {
            effects += layout(&state, code)
        }
        return effects
    }

    /// Folds a finished drag into its strip and marks the strip for the release layout.
    ///
    /// A resize whose width ends beyond the echo tolerance of its start re-weights once, trading with the
    /// neighbour on the side of the edge that moved. A move takes the reorder its last displacement calls
    /// for, whatever the drop point; the release layout then places it. Anything else snaps back to its slot.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - drag: The finished drag.
    /// - Returns: The `mirrorDirty` for the windows whose place or width changed.
    private static func settle(_ state: inout WMState, _ drag: MouseDrag) -> [WMEffect] {
        guard let code = state.stripCode(containing: drag.window), state.isActive(code),
            let strip = state.workspaces[code],
            let index = strip.columns.firstIndex(where: { $0.window == drag.window }),
            let display = state.display(forKey: strip.displayKey)
        else { return [] }
        state.relayoutOnRelease.insert(code)
        let unmoved: [WMEffect] = [.mirrorDirty(windows: [drag.window], processes: [], urgent: false)]
        if drag.mode == .move {
            var final = drag
            _ = reorder(&state, &final)
            return unmoved
        }
        let start = drag.startFrame
        let observed = drag.latestFrame
        let slots = ColumnLayout.frames(weights: strip.weights, visible: display.visibleFrame)
        let widthChange = observed.width - start.width
        if drag.mode == .resize, abs(widthChange) > echoTolerance {
            let leftEdge = abs(observed.minX - start.minX) > abs(observed.maxX - start.maxX)
            let resized = CGRect(
                x: leftEdge ? slots[index].minX - widthChange : slots[index].minX,
                y: slots[index].minY,
                width: slots[index].width + widthChange,
                height: slots[index].height
            )
            let weights = ColumnLayout.redistribute(
                weights: strip.weights,
                index: index,
                observed: resized,
                visible: display.visibleFrame
            )
            setWeights(&state, code, weights)
            return [.mirrorDirty(windows: Set(strip.columns.map(\.window)), processes: [], urgent: false)]
        }
        return unmoved
    }

    /// The layout slot of `key` in strip `code`.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - key: A tiled window.
    ///   - code: The strip holding it.
    /// - Returns: The slot, or nil when the strip, the window or its display is missing.
    private static func slot(_ state: WMState, _ key: WindowKey, in code: String) -> CGRect? {
        guard let strip = state.workspaces[code], let display = state.display(forKey: strip.displayKey),
            let index = strip.columns.firstIndex(where: { $0.window == key })
        else { return nil }
        return ColumnLayout.frames(weights: strip.weights, visible: display.visibleFrame)[index]
    }
}

// MARK: - Layout primitives

extension WMReducer {
    /// Tiles strip `code` across its display, unparking any parked window on the way.
    ///
    /// While the button is held nothing moves: the strip is recorded for the release instead. The window
    /// held by a mouse drag keeps the frame the pointer gives it until the button goes up. The floats bound to
    /// the strip come out of their park and are raised above the columns.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The strip to lay out.
    /// - Returns: One `setFrame` or `unpark` per column but the dragged one, an `unpark` per parked float and
    ///   a `raise` per shown float; none while the button is held.
    private static func layout(_ state: inout WMState, _ code: String) -> [WMEffect] {
        guard !state.mouseHeld else {
            state.relayoutOnRelease.insert(code)
            return []
        }
        state.relayoutOnRelease.remove(code)
        guard let strip = state.workspaces[code], let display = state.display(forKey: strip.displayKey) else {
            return []
        }
        let frames = ColumnLayout.frames(weights: strip.weights, visible: display.visibleFrame)
        var effects: [WMEffect] = []
        for (column, frame) in zip(strip.columns, frames) {
            let key = column.window
            if state.mouseDrag?.window == key, state.parked[key] == nil { continue }
            state.expectedFrames[key] = frame
            state.frames[key] = frame
            let wasParked = state.parked.removeValue(forKey: key) != nil
            effects.append(wasParked ? .unpark(key, frame) : .setFrame(key, frame))
        }
        for key in state.floats(boundTo: code) {
            guard let prePark = state.parked.removeValue(forKey: key) else { continue }
            state.frames[key] = prePark
            state.expectedFrames[key] = prePark
            effects.append(.unpark(key, prePark))
        }
        return effects + raiseFloats(state, code)
    }

    /// Parks every window of strip `code`, and every float bound to it, at its display's park corner.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The strip to hide.
    /// - Returns: One `park` per column and per float.
    private static func park(_ state: inout WMState, _ code: String) -> [WMEffect] {
        guard let strip = state.workspaces[code], let display = state.display(forKey: strip.displayKey) else {
            return []
        }
        let corner = ParkGeometry.parkCorner(for: display, among: state.displays)
        var effects: [WMEffect] = []
        for column in strip.columns {
            effects.append(parkWindow(&state, column.window, display: display, corner: corner))
        }
        for key in state.floats(boundTo: code) where state.mouseDrag?.window != key {
            effects.append(parkWindow(&state, key, display: display, corner: corner))
        }
        return effects
    }

    /// Parks one window, recording its pre-park frame unless it is already parked.
    ///
    /// A candidate pre-park frame that is itself hidden is skipped, so a park rect is never recorded as one.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window to hide.
    ///   - display: The display it is parked on.
    ///   - corner: The park corner of that display.
    /// - Returns: The `park` effect.
    private static func parkWindow(
        _ state: inout WMState,
        _ key: WindowKey,
        display: DisplayGeom,
        corner: ParkGeometry.Corner
    ) -> WMEffect {
        let fallback = CrashRecovery.centred(
            size: CGSize(width: display.visibleFrame.width / 2, height: display.visibleFrame.height / 2),
            in: display.visibleFrame
        )
        let candidates = [state.parked[key], state.frames[key]].compactMap(\.self)
        let prePark = candidates.first { !ParkGeometry.isParked(frame: $0, displays: state.displays) } ?? fallback
        if state.mouseDrag?.window == key { state.mouseDrag = nil }
        state.parked[key] = prePark
        let rect = ParkGeometry.parkRect(windowSize: prePark.size, display: display, corner: corner)
        state.expectedFrames[key] = rect
        state.frames[key] = rect
        return .park(key, rect)
    }

    /// Removes `key` from strip `code`, renormalizes the rest and keeps focus on a neighbour.
    ///
    /// Removing the focused column focuses its left neighbour, or the new leftmost column when it was first.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window to remove.
    ///   - code: The strip holding it.
    /// - Returns: The re-layout effects when the strip is visible.
    private static func removeColumn(_ state: inout WMState, _ key: WindowKey, from code: String) -> [WMEffect] {
        guard var strip = state.workspaces[code],
            let index = strip.columns.firstIndex(where: { $0.window == key })
        else { return [] }
        let weights = ColumnLayout.remove(weights: strip.weights, at: index)
        strip.columns.remove(at: index)
        for position in strip.columns.indices { strip.columns[position].weight = weights[position] }
        if strip.columns.isEmpty {
            strip.focusedIndex = nil
        } else if let focused = strip.focusedIndex {
            let next = focused > index ? focused - 1 : (focused == index ? index - 1 : focused)
            strip.focusedIndex = min(max(next, 0), strip.columns.count - 1)
        }
        state.workspaces[code] = strip
        return state.isActive(code) ? layout(&state, code) : []
    }

    /// Focuses the focused window of strip `code` and makes it the current strip.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The strip.
    /// - Returns: A `focus` effect then a `raise` per shown float of the strip, or none for an empty strip.
    private static func focusStrip(_ state: inout WMState, _ code: String) -> [WMEffect] {
        state.focusedWorkspace = code
        state.focusUnmanaged = false
        guard let strip = state.workspaces[code], let index = strip.focusedIndex,
            strip.columns.indices.contains(index)
        else {
            state.focused = nil
            return []
        }
        let key = strip.columns[index].window
        state.focused = key
        return [.focus(key)] + raiseFloats(state, code)
    }

    /// Stores new weights for strip `code` and re-lays it out when they changed and it is visible.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The strip.
    ///   - weights: The new weights, one per column.
    /// - Returns: The effects; none when the weights are unchanged.
    private static func applyWeights(_ state: inout WMState, _ code: String, _ weights: [Double]) -> [WMEffect] {
        guard let strip = state.workspaces[code] else { return [] }
        let unchanged = zip(strip.weights, weights).allSatisfy { abs($0 - $1) < 1e-9 }
        guard !unchanged else { return [] }
        setWeights(&state, code, weights)
        let windows = Set(strip.columns.map(\.window))
        let relayout = state.isActive(code) ? layout(&state, code) : []
        return relayout + [.mirrorDirty(windows: windows, processes: [], urgent: false)]
    }

    /// Appends `key` as the last column of strip `code` at the mean weight and renormalizes.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - key: The window to tile.
    ///   - code: The strip.
    private static func appendColumn(_ state: inout WMState, _ key: WindowKey, to code: String) {
        guard let strip = state.workspaces[code] else { return }
        var weights = strip.weights
        weights.append(ColumnLayout.appendWeight(existing: weights))
        weights = ColumnLayout.renormalize(weights)
        state.workspaces[code]?.columns.append(StripColumn(window: key, weight: weights[weights.count - 1]))
        setWeights(&state, code, weights)
        if strip.focusedIndex == nil { state.workspaces[code]?.focusedIndex = 0 }
    }

    /// Writes `weights` onto the columns of strip `code`, position by position.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The strip.
    ///   - weights: One weight per column.
    private static func setWeights(_ state: inout WMState, _ code: String, _ weights: [Double]) {
        guard let count = state.workspaces[code]?.columns.count, count == weights.count else { return }
        for position in 0..<count { state.workspaces[code]?.columns[position].weight = weights[position] }
    }

    /// The visible strip on the display under the centre of `frame`, else on the main display.
    ///
    /// A display with no strip placed on it, as between a display arriving and its configuration, defers to
    /// the main display's visible strip so a new window still tiles.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - frame: A window frame.
    /// - Returns: The workspace code, or nil when neither display shows one.
    private static func stripUnder(_ state: WMState, _ frame: CGRect) -> String? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let main = state.mainDisplay.flatMap { state.activeByDisplay[$0.key] }
        guard let display = state.displays.first(where: { $0.frame.contains(centre) }) else { return main }
        return state.activeByDisplay[display.key] ?? main
    }

    /// The effects with one frame effect per window, the last, and one trailing `mirrorDirty`.
    ///
    /// Raises follow every other effect, one per window, and a raise of a window whose last frame effect
    /// parks it is dropped. The trailing `mirrorDirty` covers every window with a frame effect or an explicit
    /// mark, and is urgent when any `park` or `unpark` survives or any mark was urgent.
    ///
    /// - Parameter effects: The raw effects.
    /// - Returns: The coalesced effects.
    static func coalesce(_ effects: [WMEffect]) -> [WMEffect] {
        var lastFrame: [WindowKey: Int] = [:]
        var lastRaise: [WindowKey: Int] = [:]
        var windows: Set<WindowKey> = []
        var processes: Set<Int32> = []
        var urgent = false
        for (index, effect) in effects.enumerated() {
            switch effect {
            case let .setFrame(key, _): lastFrame[key] = index
            case let .park(key, _), let .unpark(key, _):
                lastFrame[key] = index
                urgent = true
            case let .raise(key): lastRaise[key] = index
            case let .mirrorDirty(dirtyWindows, dirtyProcesses, dirtyUrgent):
                windows.formUnion(dirtyWindows)
                processes.formUnion(dirtyProcesses)
                urgent = urgent || dirtyUrgent
            default: break
            }
        }
        windows.formUnion(lastFrame.keys)
        var result = effects.enumerated()
            .compactMap { index, effect -> WMEffect? in
                switch effect {
                case let .setFrame(key, _), let .park(key, _), let .unpark(key, _):
                    return lastFrame[key] == index ? effect : nil
                case .mirrorDirty, .raise: return nil
                default: return effect
                }
            }
        result += survivingRaises(effects, lastRaise: lastRaise, lastFrame: lastFrame)
        if urgent || !windows.isEmpty || !processes.isEmpty {
            result.append(.mirrorDirty(windows: windows, processes: processes, urgent: urgent))
        }
        return result
    }

    /// One `raise` per raised window that does not end parked, in the order of each window's last raise.
    ///
    /// - Parameters:
    ///   - effects: The raw effects.
    ///   - lastRaise: The index of each window's last `raise`.
    ///   - lastFrame: The index of each window's last frame effect.
    /// - Returns: The surviving raises.
    private static func survivingRaises(
        _ effects: [WMEffect],
        lastRaise: [WindowKey: Int],
        lastFrame: [WindowKey: Int]
    ) -> [WMEffect] {
        lastRaise.filter { key, _ in
            guard let index = lastFrame[key], case .park = effects[index] else { return true }
            return false
        }
        .sorted { $0.value < $1.value }
        .map { .raise($0.key) }
    }
}
