import CoreGraphics
import Foundation
import XCTest

/// End-to-end behaviour of the window-manager reducer over a two-display fixture.
///
/// The main display is 1000 × 800 with a 780pt visible frame; a second 800 × 600 display sits to its right.
/// Workspaces 1 and 2 live on the main display and workspace 3 on the side display.
final class WMReducerTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_700_000_000)
    private let main = DisplayGeom(
        key: "main",
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780),
        isMain: true
    )
    private let side = DisplayGeom(
        key: "side",
        frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
        visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600),
        isMain: false
    )

    /// The window key with CoreGraphics id `id` in the fixture process.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func window(_ id: UInt32) -> WindowKey {
        WindowKey(pid: 100, launchedAt: launch, cgWindowId: id)
    }

    /// A binding with no chord that runs `action`.
    ///
    /// - Parameters:
    ///   - action: The action.
    ///   - workspace: The target workspace, for the workspace actions.
    ///   - step: The resize step, for the resize actions.
    /// - Returns: The binding.
    private func binding(_ action: HotkeyAction, _ workspace: String? = nil, step: Double? = nil) -> HotkeyBinding {
        HotkeyBinding(keyCode: 0, modifiers: 0, action: action, workspaceCode: workspace, resizeStep: step)
    }

    /// An enabled state with the given windows in workspaces 1, 2 and 3; 1 and 3 are shown.
    ///
    /// - Parameters:
    ///   - one: The columns of workspace 1.
    ///   - two: The columns of workspace 2.
    ///   - three: The columns of workspace 3.
    /// - Returns: The state after `displaysChanged` and `enable`.
    private func enabled(one: [StripColumn], two: [StripColumn] = [], three: [StripColumn] = []) -> WMState {
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

    /// The columns for window ids with weight 1 each.
    ///
    /// - Parameter ids: The window ids, left to right.
    /// - Returns: The columns.
    private func columns(_ ids: UInt32...) -> [StripColumn] {
        ids.map { StripColumn(window: window($0), weight: 1) }
    }

    /// The fixture's three workspaces with the columns `state` holds, as the service rebuilds them.
    ///
    /// - Parameter state: The reducer state.
    /// - Returns: Strips 1 and 2 on the main display and 3 on the side display.
    private func heldStrips(_ state: WMState) -> [WorkspaceStrip] {
        [("1", "main"), ("2", "main"), ("3", "side")]
            .map { code, display in
                let held = state.workspaces[code]
                return WorkspaceStrip(
                    code: code,
                    displayKey: display,
                    columns: held?.columns ?? [],
                    focusedIndex: held?.focusedIndex
                )
            }
    }

    /// A tiled observation of window `id` at `frame`.
    ///
    /// - Parameters:
    ///   - id: The window id.
    ///   - frame: The observed frame.
    /// - Returns: The observation.
    private func observed(_ id: UInt32, _ frame: CGRect = CGRect(x: 0, y: 0, width: 500, height: 780)) -> ObservedWindow
    {
        ObservedWindow(key: window(id), frame: frame, classification: .tiled, title: nil)
    }

    /// A press point on the main display's title-bar row.
    ///
    /// - Parameters:
    ///   - x: The pointer's x.
    ///   - y: The pointer's y; defaults to just under the visible frame's top edge.
    /// - Returns: The point.
    private func press(_ x: CGFloat, _ y: CGFloat = 770) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    /// A full-height frame on the main display at `x` with `width`.
    ///
    /// - Parameters:
    ///   - x: The left edge.
    ///   - width: The width.
    /// - Returns: The frame.
    private func at(_ x: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 780)
    }

    /// True when `effects` parks `key`.
    ///
    /// - Parameters:
    ///   - effects: Reducer output.
    ///   - key: The window.
    /// - Returns: Whether a `park` for `key` is present.
    private func parks(_ effects: [WMEffect], _ key: WindowKey) -> Bool {
        effects.contains { if case .park(key, _) = $0 { true } else { false } }
    }

    /// The frame effects in `effects`, keyed by window.
    ///
    /// - Parameter effects: Reducer output.
    /// - Returns: The requested frame per window.
    private func frames(_ effects: [WMEffect]) -> [WindowKey: CGRect] {
        var result: [WindowKey: CGRect] = [:]
        for effect in effects {
            switch effect {
            case let .setFrame(key, frame), let .park(key, frame), let .unpark(key, frame): result[key] = frame
            default: break
            }
        }
        return result
    }

    func testEnableRegistersHotkeysFirst() {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([main]))
        let strips = [WorkspaceStrip(code: "1", displayKey: "main")]
        let effects = WMReducer.reduce(&state, .enable(strips: strips, active: ["main": "1"]))
        XCTAssertEqual(effects.first, .registerHotkeys(KeyCodeTable.bindings))
        XCTAssertTrue(state.enabled)
    }

    func testFocusLeftAndRightStopAtBothEdges() {
        var state = enabled(one: columns(1, 2, 3))
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusLeft))), [.focus(window(1))])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusLeft))), [])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusRight))), [.focus(window(2))])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusRight))), [.focus(window(3))])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusRight))), [])
        XCTAssertEqual(state.focused, window(3))
    }

    func testSlideStopsAtEdgesAndWeightsTravelWithWindows() {
        let one = [StripColumn(window: window(1), weight: 1.5), StripColumn(window: window(2), weight: 0.5)]
        var state = enabled(one: one)
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.slideLeft))), [])
        let effects = WMReducer.reduce(&state, .hotkey(binding(.slideRight)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
        XCTAssertEqual(state.workspaces["1"]?.weights, [0.5, 1.5])
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 1)
        XCTAssertEqual(frames(effects)[window(2)], CGRect(x: 0, y: 0, width: 250, height: 780))
        XCTAssertEqual(frames(effects)[window(1)], CGRect(x: 250, y: 0, width: 750, height: 780))
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.slideRight))), [])
    }

    func testMoveToHiddenWorkspaceParksAndAppendsAtMeanWeight() {
        let two = [StripColumn(window: window(3), weight: 2), StripColumn(window: window(4), weight: 1)]
        var state = enabled(one: columns(1, 2), two: two)
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        let effects = WMReducer.reduce(&state, .hotkey(binding(.moveToWorkspace, "2")))
        XCTAssertTrue(effects.contains { if case .park(window(1), _) = $0 { true } else { false } })
        let target = state.workspaces["2"]?.columns ?? []
        XCTAssertEqual(target.map(\.window), [window(3), window(4), window(1)])
        XCTAssertEqual(target[2].weight, (target[0].weight + target[1].weight) / 2, accuracy: 1e-9)
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2)])
        XCTAssertEqual(frames(effects)[window(2)], main.visibleFrame)
        XCTAssertNotNil(state.parked[window(1)])
        XCTAssertEqual(effects.last, .mirrorDirty(windows: [window(1), window(2)], processes: [], urgent: true))
    }

    func testFocusWorkspaceParksOldUnparksNewAndPersistsUrgently() {
        var state = enabled(one: columns(1), two: columns(2))
        XCTAssertNotNil(state.parked[window(2)])
        let effects = WMReducer.reduce(&state, .hotkey(binding(.focusWorkspace, "2")))
        XCTAssertTrue(effects.contains { if case .park(window(1), _) = $0 { true } else { false } })
        XCTAssertTrue(effects.contains(.unpark(window(2), main.visibleFrame)))
        XCTAssertTrue(effects.contains(.persistActiveWorkspace(displayKey: "main", workspaceCode: "2")))
        XCTAssertTrue(effects.contains(.focus(window(2))))
        guard case let .mirrorDirty(_, _, urgent)? = effects.last else { return XCTFail("no trailing mirrorDirty") }
        XCTAssertTrue(urgent)
        XCTAssertEqual(state.activeByDisplay["main"], "2")
        XCTAssertNil(state.parked[window(2)])
        XCTAssertNotNil(state.parked[window(1)])
    }

    func testResizeHotkeyConservesWeightSumAndClampsToMinimumWidth() {
        var state = enabled(one: columns(1, 2))
        let grown = WMReducer.reduce(&state, .hotkey(binding(.resizeGrow, step: 50)))
        XCTAssertEqual(state.workspaces["1"]?.weights.reduce(0, +) ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(frames(grown)[window(1)]?.width, 550)
        XCTAssertEqual(frames(grown)[window(2)]?.width, 450)
        let clamped = WMReducer.reduce(&state, .hotkey(binding(.resizeGrow, step: 5000)))
        XCTAssertEqual(frames(clamped)[window(2)]?.width, ColumnLayout.defaultMinWidth)
        XCTAssertEqual(state.workspaces["1"]?.weights.reduce(0, +) ?? 0, 2, accuracy: 1e-9)
    }

    func testEchoResizeIsIgnoredAndUserResizeReweightsOnRelease() {
        var state = enabled(one: columns(1, 2))
        let echo = CGRect(x: 0, y: 0, width: 501, height: 780)
        let drag = CGRect(x: 0, y: 0, width: 600, height: 780)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(1), echo)), [])
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(1), drag)), [])
        let effects = WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 600, y: 400)))
        XCTAssertEqual(frames(effects)[window(1)], drag)
        XCTAssertEqual(frames(effects)[window(2)], CGRect(x: 600, y: 0, width: 400, height: 780))
    }

    func testNothingMovesWhileTheButtonIsHeld() {
        var state = enabled(one: columns(1, 2, 3), two: columns(5))
        let created = CGRect(x: 10, y: 10, width: 300, height: 300)
        let held: [WMEvent] = [
            .mousePressed(at: press(500)),
            .windowMoved(window(2), CGRect(x: 400, y: 50, width: 334, height: 780)),
            .windowCreated(window(9), frame: created, classification: .tiled, title: nil),
            .windowFocused(window(5)),
            .displaysChanged([main, side]),
            .windowResized(window(2), CGRect(x: 420, y: 50, width: 334, height: 780)),
            .windowResized(window(2), CGRect(x: 440, y: 50, width: 400, height: 780)),
            .windowMoved(window(2), CGRect(x: 430, y: 60, width: 400, height: 780)),
            .wake,
            .reconcile(observed: [observed(1), observed(2), observed(3), observed(5), observed(9)], answered: [100]),
        ]
        for event in held { XCTAssertEqual(frames(WMReducer.reduce(&state, event)), [:], "\(event)") }
        XCTAssertEqual(state.mouseDrag?.window, window(2))
        XCTAssertEqual(state.activeByDisplay["main"], "1")
        XCTAssertFalse(state.knows(window(9)))
        XCTAssertNotNil(state.parked[window(5)])
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 500, y: 400))))
        XCTAssertNotNil(released[window(1)])
        XCTAssertNotNil(released[window(2)])
        XCTAssertNotNil(released[window(3)])
        XCTAssertTrue(state.relayoutOnRelease.isEmpty)
        XCTAssertFalse(state.displaysPendingRelease)
    }

    func testAWindowCreatedWhileHeldIsAdoptedByTheFirstReconcileAfterRelease() {
        var state = enabled(one: columns(1))
        let created = CGRect(x: 10, y: 10, width: 300, height: 300)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: created, classification: .tiled, title: nil))
        XCTAssertFalse(state.knows(window(9)))
        _ = WMReducer.reduce(&state, .mouseReleased(at: nil))
        let effects = WMReducer.reduce(
            &state,
            .reconcile(observed: [observed(1), observed(9, created)], answered: [100])
        )
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(9)])
        XCTAssertEqual(frames(effects)[window(9)], CGRect(x: 500, y: 0, width: 500, height: 780))
    }

    func testANeighboursEventWhileHeldCannotClaimTheDrag() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(3), CGRect(x: 690, y: 5, width: 333, height: 780))),
            []
        )
        XCTAssertNil(state.mouseDrag)
        _ = WMReducer.reduce(&state, .windowMoved(window(2), CGRect(x: 350, y: 20, width: 334, height: 780)))
        XCTAssertEqual(state.mouseDrag?.window, window(2))
        _ = WMReducer.reduce(&state, .windowResized(window(1), CGRect(x: 0, y: 0, width: 250, height: 780)))
        XCTAssertEqual(state.mouseDrag?.window, window(2))
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 500, y: 400))))
        XCTAssertEqual(released[window(3)], CGRect(x: 667, y: 0, width: 333, height: 780))
    }

    func testAHotkeyWhileHeldStillApplies() {
        var state = enabled(one: columns(1), two: columns(2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        let effects = WMReducer.reduce(&state, .hotkey(binding(.focusWorkspace, "2")))
        XCTAssertTrue(effects.contains(.unpark(window(2), main.visibleFrame)))
        XCTAssertTrue(parks(effects, window(1)))
        XCTAssertEqual(state.activeByDisplay["main"], "2")
        XCTAssertTrue(state.mouseHeld)
    }

    func testAConfigureWhileHeldAppliesOnRelease() {
        var state = enabled(one: columns(1), two: columns(2))
        let strips = [WorkspaceStrip(code: "1", displayKey: "main"), WorkspaceStrip(code: "3", displayKey: "side")]
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        XCTAssertEqual(WMReducer.reduce(&state, .configure(strips: strips, active: [:])), [])
        XCTAssertNotNil(state.workspaces["2"])
        let effects = WMReducer.reduce(&state, .mouseReleased(at: nil))
        XCTAssertNil(state.workspaces["2"])
        XCTAssertTrue(effects.contains { if case .unpark(window(2), _) = $0 { true } else { false } })
    }

    func testDraggingANonFocusedWindowClaimsTheDragAndReorders() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        let effects = WMReducer.reduce(&state, .windowMoved(window(2), at(633, 334)))
        XCTAssertEqual(state.mouseDrag?.window, window(2))
        XCTAssertEqual(effects, [.setFrame(window(3), at(333, 334))])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(3), window(2)])
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 2)
    }

    func testTheDropPointNeverDecidesTheReorder() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(2), at(380, 334))), [])
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: press(850, 795))))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2), window(3)])
        XCTAssertEqual(released[window(2)], at(333, 334))
    }

    func testTheGrabPointDoesNotChangeTheDisplacementThatSwaps() {
        for grab: CGFloat in [5, 495] {
            var state = enabled(one: columns(1, 2))
            _ = WMReducer.reduce(&state, .mousePressed(at: press(grab)))
            XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(160, 500))), [], "grab=\(grab)")
            XCTAssertEqual(
                WMReducer.reduce(&state, .windowMoved(window(1), at(167, 500))),
                [.setFrame(window(2), at(0, 500))],
                "grab=\(grab)"
            )
        }
    }

    func testASwapFiresAtThirtyFourPercentOfTheNeighbourAndNotAtThirty() {
        var state = enabled(one: columns(1, 2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(150, 500))), [])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(1), at(170, 500))),
            [.setFrame(window(2), at(0, 500))]
        )
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
    }

    func testANarrowWindowPassesAWideNeighbourAndBackWithoutThrashing() {
        let one = [StripColumn(window: window(1), weight: 0.5), StripColumn(window: window(2), weight: 1.5)]
        var state = enabled(one: one)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(125)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(240, 250))), [])
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(1), at(250, 250))),
            [.setFrame(window(2), at(0, 750))]
        )
        for x: CGFloat in [240, 255, 100, 260, 1] {
            XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(x, 250))), [], "x=\(x)")
        }
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(1), at(0, 250))),
            [.setFrame(window(2), at(250, 750))]
        )
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
    }

    func testAWideWindowPassesANarrowNeighbourAndBackWithoutThrashing() {
        let one = [StripColumn(window: window(1), weight: 0.5), StripColumn(window: window(2), weight: 1.5)]
        var state = enabled(one: one)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(625)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(2), at(170, 750))), [])
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(2), at(166, 750))),
            [.setFrame(window(1), at(750, 250))]
        )
        for x: CGFloat in [170, 160, 200, 150, 249] {
            XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(2), at(x, 750))), [], "x=\(x)")
        }
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(2), at(250, 750))),
            [.setFrame(window(1), at(0, 250))]
        )
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
    }

    func testAnAppSnappedWidthIsStillAMove() {
        var state = enabled(one: columns(1, 2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        _ = WMReducer.reduce(&state, .windowMoved(window(1), at(20, 495)))
        XCTAssertEqual(state.mouseDrag?.mode, .move)
        _ = WMReducer.reduce(&state, .windowMoved(window(1), at(450, 495)))
        XCTAssertEqual(state.mouseDrag?.mode, .move)
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: nil)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
        XCTAssertEqual(state.workspaces["1"]?.weights, [1, 1])
        XCTAssertEqual(released[window(1)], at(500, 500))
    }

    func testCrossingAThirdIntoTheRightNeighbourMovesOnlyTheNeighbour() {
        var state = enabled(one: columns(1, 2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(100, 500))), [])
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(1), at(430, 500))),
            [.setFrame(window(2), at(0, 500))]
        )
        XCTAssertEqual(state.expectedFrames[window(2)], at(0, 500))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(2), at(0, 500))), [])
    }

    func testHoveringAtTheBoundaryDoesNotThrash() {
        var state = enabled(one: columns(1, 2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(170, 500))).count, 1)
        for x: CGFloat in [160, 175, 150, 180, 10, 1] {
            XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(x, 500))), [], "x=\(x)")
        }
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
        XCTAssertEqual(
            WMReducer.reduce(&state, .windowMoved(window(1), at(0, 500))),
            [.setFrame(window(2), at(500, 500))]
        )
        for x: CGFloat in [5, 160, 20, 166] {
            XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(x, 500))), [], "x=\(x)")
        }
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
    }

    func testAFastFlickAcrossTwoNeighboursMovesOnlyTheNeighbours() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(150)))
        let effects = WMReducer.reduce(&state, .windowMoved(window(1), at(700, 333)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(3), window(1)])
        XCTAssertEqual(effects.count, 2)
        XCTAssertEqual(frames(effects), [window(2): at(0, 333), window(3): at(333, 334)])
    }

    func testWidthsTravelWithTheWindowsInALiveReorder() {
        let one = [StripColumn(window: window(1), weight: 1.5), StripColumn(window: window(2), weight: 0.5)]
        var state = enabled(one: one)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(375)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(80, 750))), [])
        let effects = WMReducer.reduce(&state, .windowMoved(window(1), at(90, 750)))
        XCTAssertEqual(effects, [.setFrame(window(2), at(0, 250))])
        XCTAssertEqual(state.workspaces["1"]?.weights, [0.5, 1.5])
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), at(10, 750))), [])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
    }

    func testReleaseLaysTheStripOutOnceWithTheDraggedWindowInItsFinalSlot() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(150)))
        _ = WMReducer.reduce(&state, .windowMoved(window(1), at(700, 333)))
        let effects = WMReducer.reduce(&state, .mouseReleased(at: press(850)))
        let setFrames = effects.filter { if case .setFrame = $0 { true } else { false } }
        XCTAssertEqual(setFrames.count, 3)
        XCTAssertEqual(frames(effects)[window(1)], at(667, 333))
        XCTAssertEqual(state.expectedFrames[window(1)], at(667, 333))
        XCTAssertNil(state.mouseDrag)
        XCTAssertTrue(state.relayoutOnRelease.isEmpty)
    }

    func testANilReleaseUsesTheLastDisplacement() {
        var state = enabled(one: columns(1, 2))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(250)))
        _ = WMReducer.reduce(&state, .windowMoved(window(1), at(100, 500)))
        _ = WMReducer.reduce(&state, .windowMoved(window(1), at(430, 500)))
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: nil)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(1)])
        XCTAssertEqual(released[window(1)], at(500, 500))
    }

    func testAResizeDragNeverReorders() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(2), at(333, 434))), [])
        XCTAssertEqual(state.mouseDrag?.mode, .resize)
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(2), at(700, 434))), [])
        _ = WMReducer.reduce(&state, .mouseReleased(at: press(900)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2), window(3)])
    }

    func testReleasingAMovedWindowOverItsOwnSlotSnapsItBack() {
        var state = enabled(one: columns(1, 2))
        let dragged = CGRect(x: 100, y: 30, width: 500, height: 780)
        _ = WMReducer.reduce(&state, .mousePressed(at: press(200)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowMoved(window(1), dragged)), [])
        let effects = WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 300, y: 400)))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
        XCTAssertEqual(frames(effects)[window(1)], CGRect(x: 0, y: 0, width: 500, height: 780))
        XCTAssertEqual(WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 300, y: 400))), [])
    }

    func testAnEdgeDragSettlesOnceOnReleaseFromItsStart() {
        var state = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .mousePressed(at: press(500)))
        let wide = CGRect(x: 333, y: 0, width: 434, height: 780)
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(2), wide)), [])
        let narrower = CGRect(x: 333, y: 0, width: 384, height: 780)
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(2), narrower)), [])
        let released = frames(WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 900, y: 400))))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2), window(3)])
        XCTAssertEqual(released[window(2)], narrower)
        XCTAssertEqual(released[window(3)], CGRect(x: 717, y: 0, width: 283, height: 780))
        XCTAssertEqual(state.workspaces["1"]?.weights.reduce(0, +) ?? 0, 3, accuracy: 1e-9)
    }

    func testWindowDestroyedRenormalizesTheStrip() {
        let one = [1.0, 2.0, 3.0].enumerated()
            .map { StripColumn(window: window(UInt32($0.offset + 1)), weight: $0.element) }
        var state = enabled(one: one)
        let effects = WMReducer.reduce(&state, .windowDestroyed(window(2)))
        XCTAssertEqual(state.workspaces["1"]?.weights, [0.5, 1.5])
        XCTAssertEqual(frames(effects)[window(1)], CGRect(x: 0, y: 0, width: 250, height: 780))
        XCTAssertEqual(frames(effects)[window(3)], CGRect(x: 250, y: 0, width: 750, height: 780))
    }

    func testNewStandardWindowAppendsToTheVisibleStripAtMeanWeight() {
        var state = enabled(one: columns(1))
        let effects = WMReducer.reduce(
            &state,
            .windowCreated(
                window(9),
                frame: CGRect(x: 100, y: 100, width: 300, height: 300),
                classification: .tiled,
                title: nil
            )
        )
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(9)])
        XCTAssertEqual(frames(effects)[window(9)], CGRect(x: 500, y: 0, width: 500, height: 780))
    }

    func testMinimizedAndFullscreenWindowsNeverEnterAColumn() {
        var state = enabled(one: columns(1))
        let frame = CGRect(x: 100, y: 100, width: 300, height: 300)
        let minimized = WindowClassifier.classify(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isMinimized: true,
            isFullscreen: false
        )
        let fullscreen = WindowClassifier.classify(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isMinimized: false,
            isFullscreen: true
        )
        _ = WMReducer.reduce(&state, .windowCreated(window(7), frame: frame, classification: minimized, title: nil))
        _ = WMReducer.reduce(&state, .windowCreated(window(8), frame: frame, classification: fullscreen, title: nil))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1)])
        XCTAssertEqual(state.floating, [window(7), window(8)])
    }

    func testDisplaysChangedDroppingADisplayDropsItsActiveEntryAndLeavesItsStripHidden() {
        var state = enabled(one: columns(1), three: columns(5))
        let effects = WMReducer.reduce(&state, .displaysChanged([main]))
        XCTAssertNil(state.activeByDisplay["side"])
        XCTAssertEqual(state.activeByDisplay["main"], "1")
        XCTAssertEqual(state.workspaces["3"]?.displayKey, "side")
        XCTAssertFalse(state.isActive("3"))
        XCTAssertEqual(state.workspaces["3"]?.columns.map(\.window), [window(5)])
        XCTAssertNil(frames(effects)[window(5)])
        XCTAssertFalse(effects.contains { if case .persistActiveWorkspace = $0 { true } else { false } })
    }

    func testAnEmptyDisplayArrangementKeepsTheVisibleWorkspaces() {
        var state = enabled(one: columns(1), two: columns(2), three: columns(3))
        _ = WMReducer.reduce(&state, .hotkey(binding(.focusWorkspace, "2")))
        _ = WMReducer.reduce(&state, .displaysChanged([]))
        XCTAssertEqual(state.activeByDisplay, ["main": "2", "side": "3"])
        let effects = WMReducer.reduce(&state, .displaysChanged([main, side]))
        XCTAssertEqual(state.activeByDisplay, ["main": "2", "side": "3"])
        XCTAssertFalse(effects.contains { if case .persistActiveWorkspace = $0 { true } else { false } })
    }

    func testDisableUnparksEveryParkedWindowAndUnregistersHotkeys() {
        var state = enabled(one: columns(1), two: columns(2, 3))
        let prePark = state.parked
        XCTAssertEqual(Set(prePark.keys), [window(2), window(3)])
        let effects = WMReducer.reduce(&state, .disable)
        for (key, frame) in prePark { XCTAssertTrue(effects.contains(.unpark(key, frame))) }
        XCTAssertTrue(effects.contains(.unregisterAllHotkeys))
        XCTAssertTrue(state.parked.isEmpty)
        XCTAssertFalse(state.enabled)
    }

    func testEventsAreIgnoredWhileDisabled() {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([main]))
        let frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let created = WMEvent.windowCreated(window(1), frame: frame, classification: .tiled, title: nil)
        XCTAssertEqual(WMReducer.reduce(&state, created), [])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(binding(.focusRight))), [])
    }

    func testRepeatedEnableAndDisableReturnAHiddenWindowToItsOriginalFrame() {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([main, side]))
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        state.frames[window(2)] = original
        for _ in 0..<2 {
            let enable = WMEvent.enable(strips: heldStrips(state), active: ["main": "1", "side": "3"])
            if state.workspaces.isEmpty {
                let strips = [
                    WorkspaceStrip(code: "1", displayKey: "main", columns: columns(1)),
                    WorkspaceStrip(code: "2", displayKey: "main", columns: columns(2)),
                    WorkspaceStrip(code: "3", displayKey: "side"),
                ]
                _ = WMReducer.reduce(&state, .enable(strips: strips, active: ["main": "1", "side": "3"]))
            } else {
                _ = WMReducer.reduce(&state, enable)
            }
            XCTAssertEqual(state.parked[window(2)], original)
            XCTAssertEqual(frames(WMReducer.reduce(&state, .disable))[window(2)], original)
        }
    }

    func testEnableFocusDisableEnableDisableLeavesEveryWindowOnScreen() {
        var state = enabled(one: columns(1), two: columns(2))
        _ = WMReducer.reduce(&state, .hotkey(binding(.focusWorkspace, "2")))
        XCTAssertEqual(frames(WMReducer.reduce(&state, .disable))[window(1)], main.visibleFrame)
        _ = WMReducer.reduce(
            &state,
            .enable(strips: heldStrips(state), active: ["main": "2", "side": "3"])
        )
        XCTAssertEqual(state.parked[window(1)], main.visibleFrame)
        let last = frames(WMReducer.reduce(&state, .disable))
        XCTAssertEqual(last[window(1)], main.visibleFrame)
        for (key, frame) in last {
            XCTAssertFalse(ParkGeometry.isParked(frame: frame, displays: [main, side]), "\(key) left parked")
        }
    }

    func testReconcileKeepsTheWindowsOfAPidThatDidNotAnswer() {
        var state = enabled(one: columns(1), two: columns(2))
        let before = state
        XCTAssertEqual(WMReducer.reduce(&state, .reconcile(observed: [], answered: [])), [])
        XCTAssertEqual(state, before)
    }

    func testReconcileDestroysAMissingWindowOfAnAnsweringPid() {
        var state = enabled(one: columns(1), two: columns(2))
        _ = WMReducer.reduce(&state, .reconcile(observed: [observed(1)], answered: [100]))
        XCTAssertEqual(state.workspaces["2"]?.columns, [])
        XCTAssertNil(state.parked[window(2)])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1)])
    }

    func testFocusingAWindowOfAHiddenWorkspaceShowsIt() {
        var state = enabled(one: columns(1), two: columns(2))
        let effects = WMReducer.reduce(&state, .windowFocused(window(2)))
        XCTAssertEqual(state.activeByDisplay["main"], "2")
        XCTAssertTrue(effects.contains(.unpark(window(2), main.visibleFrame)))
        XCTAssertTrue(parks(effects, window(1)))
        XCTAssertEqual(state.focused, window(2))
    }

    func testAppTerminatedForgetsItsParkedWindowsWithoutUnparking() {
        let other = WindowKey(pid: 200, launchedAt: launch, cgWindowId: 9)
        var state = enabled(one: columns(1) + [StripColumn(window: other, weight: 1)], two: columns(2, 3))
        let effects = WMReducer.reduce(&state, .appTerminated(pid: 100))
        XCTAssertTrue(state.parked.isEmpty)
        XCTAssertEqual(state.allWindows, [other])
        XCTAssertFalse(effects.contains { if case .unpark = $0 { true } else { false } })
        let dirty = WMEffect.mirrorDirty(
            windows: [window(1), window(2), window(3), other],
            processes: [100],
            urgent: false
        )
        XCTAssertEqual(effects.last, dirty)
    }

    func testConfigureWithUnchangedStripsMovesNothingAndKeepsParkedAndFloating() {
        var state = enabled(one: columns(1), two: columns(2))
        let minimized = WindowClassifier.classify(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isMinimized: true,
            isFullscreen: false
        )
        let frame = CGRect(x: 100, y: 100, width: 300, height: 300)
        _ = WMReducer.reduce(&state, .windowCreated(window(7), frame: frame, classification: minimized, title: nil))
        let parked = state.parked
        let floating = state.floating
        let strips = heldStrips(WMState())
        let effects = WMReducer.reduce(&state, .configure(strips: strips, active: ["main": "1"]))
        XCTAssertEqual(frames(effects), [:])
        XCTAssertFalse(effects.contains { if case .registerHotkeys = $0 { true } else { false } })
        XCTAssertEqual(state.parked, parked)
        XCTAssertEqual(state.floating, floating)
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(2)])
    }

    func testConfigureReHomesAHiddenStrip() {
        var state = enabled(one: columns(1), two: columns(2))
        let strips = [
            WorkspaceStrip(code: "1", displayKey: "main"),
            WorkspaceStrip(code: "2", displayKey: "side"),
            WorkspaceStrip(code: "3", displayKey: "side"),
        ]
        let effects = WMReducer.reduce(&state, .configure(strips: strips, active: [:]))
        XCTAssertFalse(effects.contains { if case .registerHotkeys = $0 { true } else { false } })
        XCTAssertEqual(state.workspaces["2"]?.displayKey, "side")
        guard let parkedFrame = frames(effects)[window(2)] else { return XCTFail("window 2 was not re-parked") }
        XCTAssertTrue(ParkGeometry.isParked(frame: parkedFrame, displays: [main, side]))
        XCTAssertNil(frames(effects)[window(1)])
    }

    func testConfigureDeletingAWorkspaceMovesItsWindowsToTheVisibleStripOfItsDisplay() {
        var state = enabled(one: columns(1), two: columns(2))
        let strips = [WorkspaceStrip(code: "1", displayKey: "main"), WorkspaceStrip(code: "3", displayKey: "side")]
        let effects = WMReducer.reduce(&state, .configure(strips: strips, active: [:]))
        XCTAssertNil(state.workspaces["2"])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
        XCTAssertTrue(effects.contains { if case .unpark(window(2), _) = $0 { true } else { false } })
        XCTAssertTrue(state.parked.isEmpty)
    }

    func testAResizeWithoutADragAcceptsTheClampedFrameWithoutReweighting() {
        var state = enabled(one: columns(1, 2))
        let clamped = CGRect(x: 0, y: 0, width: 700, height: 780)
        let effects = WMReducer.reduce(&state, .windowResized(window(1), clamped))
        XCTAssertEqual(frames(effects), [:])
        XCTAssertEqual(state.workspaces["1"]?.weights, [1, 1])
        XCTAssertEqual(state.expectedFrames[window(1)], clamped)
        XCTAssertEqual(WMReducer.reduce(&state, .windowResized(window(1), clamped)), [])
    }

    func testDraggingALeftEdgeTradesWithTheLeftNeighbourAndARightEdgeWithTheRight() {
        var left = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&left, .mousePressed(at: press(500)))
        _ = WMReducer.reduce(&left, .windowResized(window(2), CGRect(x: 300, y: 0, width: 367, height: 780)))
        _ = WMReducer.reduce(&left, .windowResized(window(2), CGRect(x: 233, y: 0, width: 434, height: 780)))
        let leftFrames = frames(WMReducer.reduce(&left, .mouseReleased(at: CGPoint(x: 233, y: 400))))
        XCTAssertEqual(leftFrames[window(1)]?.width, 233)
        XCTAssertEqual(leftFrames[window(2)], CGRect(x: 233, y: 0, width: 434, height: 780))
        XCTAssertEqual(leftFrames[window(3)], CGRect(x: 667, y: 0, width: 333, height: 780))
        var right = enabled(one: columns(1, 2, 3))
        _ = WMReducer.reduce(&right, .mousePressed(at: press(500)))
        _ = WMReducer.reduce(&right, .windowResized(window(2), CGRect(x: 333, y: 0, width: 434, height: 780)))
        let rightFrames = frames(WMReducer.reduce(&right, .mouseReleased(at: CGPoint(x: 767, y: 400))))
        XCTAssertEqual(rightFrames[window(1)]?.width, 333)
        XCTAssertEqual(rightFrames[window(2)], CGRect(x: 333, y: 0, width: 434, height: 780))
        XCTAssertEqual(rightFrames[window(3)], CGRect(x: 767, y: 0, width: 233, height: 780))
    }

    func testConfigureWithANewPlacementShowsExactlyOneStripPerConnectedDisplay() {
        var state = enabled(one: columns(1), two: columns(2), three: columns(3))
        let strips = [
            WorkspaceStrip(code: "1", displayKey: "main"),
            WorkspaceStrip(code: "2", displayKey: "side"),
            WorkspaceStrip(code: "3", displayKey: "side"),
        ]
        let effects = WMReducer.reduce(&state, .configure(strips: strips, active: ["side": "2"]))
        for display in [main, side] {
            let shown = state.workspaceOrder.filter {
                state.isActive($0) && state.workspaces[$0]?.displayKey == display.key
            }
            XCTAssertEqual(shown.count, 1, display.key)
        }
        XCTAssertEqual(state.activeByDisplay, ["main": "1", "side": "2"])
        XCTAssertTrue(effects.contains(.unpark(window(2), side.visibleFrame)))
        XCTAssertTrue(parks(effects, window(3)))
    }

    func testConfigureActiveReplacesTheVisibleCodeOnAWorkstationSwitch() {
        var state = enabled(one: columns(1), two: columns(2))
        let effects = WMReducer.reduce(
            &state,
            .configure(strips: heldStrips(state), active: ["main": "2", "side": "3"])
        )
        XCTAssertEqual(state.activeByDisplay["main"], "2")
        XCTAssertTrue(effects.contains(.unpark(window(2), main.visibleFrame)))
        XCTAssertTrue(parks(effects, window(1)))
    }

    func testAWindowKeepsItsCodeWhenAConfigureMovesTheCodeToAnotherDisplay() {
        var state = enabled(one: columns(1), two: columns(2))
        let strips = [
            WorkspaceStrip(code: "1", displayKey: "side"),
            WorkspaceStrip(code: "2", displayKey: "main"),
            WorkspaceStrip(code: "3", displayKey: "side"),
        ]
        let effects = WMReducer.reduce(
            &state,
            .configure(strips: strips, active: ["main": "2", "side": "1"])
        )
        XCTAssertEqual(state.stripCode(containing: window(1)), "1")
        XCTAssertEqual(state.workspaces["1"]?.displayKey, "side")
        XCTAssertEqual(frames(effects)[window(1)], side.visibleFrame)
        XCTAssertEqual(state.stripCode(containing: window(2)), "2")
    }

    func testFocusingACodeOnAnotherDisplayShowsItThereWithoutPullingItAcross() {
        var state = enabled(one: columns(1), three: columns(3, 4))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        let effects = WMReducer.reduce(&state, .hotkey(binding(.focusWorkspace, "3")))
        XCTAssertEqual(state.workspaces["3"]?.displayKey, "side")
        XCTAssertEqual(state.activeByDisplay, ["main": "1", "side": "3"])
        XCTAssertEqual(effects, [.focus(window(3))])
        XCTAssertEqual(state.focusedWorkspace, "3")
    }

    func testAWindowOnADisplayWithNoStripTilesIntoTheMainDisplaysVisibleStrip() {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([main, side]))
        let only = [WorkspaceStrip(code: "1", displayKey: "main")]
        _ = WMReducer.reduce(&state, .enable(strips: only, active: ["main": "1"]))
        XCTAssertNil(state.activeByDisplay["side"])
        let onSide = CGRect(x: 1100, y: 100, width: 300, height: 300)
        _ = WMReducer.reduce(&state, .windowCreated(window(4), frame: onSide, classification: .tiled, title: nil))
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(4)])
        XCTAssertEqual(state.frames[window(4)], main.visibleFrame)
    }

    func testNoStripCodeOutsideTheWorkspaceCodesEverAppears() {
        let codes = Set(MachineHostPlacement.WorkspaceCodes.all)
        var state = enabled(one: columns(1), two: columns(2), three: columns(3))
        let onSide = CGRect(x: 1100, y: 100, width: 300, height: 300)
        let events: [WMEvent] = [
            .displaysChanged([main]),
            .windowCreated(window(4), frame: onSide, classification: .tiled, title: nil),
            .displaysChanged([main, side]),
            .configure(strips: [WorkspaceStrip(code: "1", displayKey: "main")], active: [:]),
            .windowCreated(window(5), frame: onSide, classification: .tiled, title: nil),
            .disable,
            .enable(strips: heldStrips(state), active: ["main": "1"]),
        ]
        for event in events {
            _ = WMReducer.reduce(&state, event)
            XCTAssertTrue(Set(state.workspaces.keys).isSubset(of: codes), "\(event)")
            XCTAssertTrue(Set(state.workspaceOrder).isSubset(of: codes), "\(event)")
            XCTAssertTrue(Set(state.activeByDisplay.values).isSubset(of: codes), "\(event)")
        }
    }

    func testTheTableBindsOptionHToShowWorkspaceH() {
        let optionH = KeyCodeTable.bindings.filter {
            $0.keyCode == KeyCodeTable.codes["h"] && $0.modifiers == ModifierMask.option
        }
        XCTAssertEqual(optionH.map(\.action), [.focusWorkspace])
        XCTAssertEqual(optionH.first?.workspaceCode, "H")
        XCTAssertEqual(KeyCodeTable.chordLabel(for: optionH[0]), "⌥H")
    }

    func testTheTableBindsEveryCodeOnceAndNoChordTwice() {
        let bindings = KeyCodeTable.bindings
        let codes = MachineHostPlacement.WorkspaceCodes.all
        let chords = bindings.map { "\($0.keyCode)/\($0.modifiers)" }
        XCTAssertEqual(Set(chords).count, chords.count)
        for action in [HotkeyAction.focusWorkspace, .moveToWorkspace] {
            XCTAssertEqual(bindings.filter { $0.action == action }.compactMap(\.workspaceCode), codes)
        }
        let directions: Set<HotkeyAction> = [.focusLeft, .focusRight, .slideLeft, .slideRight]
        for binding in bindings where directions.contains(binding.action) {
            XCTAssertTrue([KeyCodeTable.leftArrow, KeyCodeTable.rightArrow].contains(binding.keyCode))
        }
        XCTAssertEqual(bindings.count, codes.count * 2 + 6)
    }

    func testControlOptionArrowsDispatchColumnFocusAndOptionArrowsStayFree() {
        var state = enabled(one: columns(1, 2, 3))
        let arrows = [KeyCodeTable.leftArrow, KeyCodeTable.rightArrow]
        let wordNavigation = [ModifierMask.option, ModifierMask.option | ModifierMask.shift]
        XCTAssertFalse(
            KeyCodeTable.bindings.contains { arrows.contains($0.keyCode) && wordNavigation.contains($0.modifiers) }
        )
        let controlOption = ModifierMask.control | ModifierMask.option
        let chord = { (key: UInt32, modifiers: UInt32) in
            KeyCodeTable.bindings.first { $0.keyCode == key && $0.modifiers == modifiers }
        }
        guard let right = chord(KeyCodeTable.rightArrow, controlOption),
            let left = chord(KeyCodeTable.leftArrow, controlOption)
        else { return XCTFail("no Control-Option-arrow chord") }
        XCTAssertEqual(chord(KeyCodeTable.leftArrow, controlOption | ModifierMask.shift)?.action, .slideLeft)
        XCTAssertEqual(chord(KeyCodeTable.rightArrow, controlOption | ModifierMask.shift)?.action, .slideRight)
        XCTAssertEqual(KeyCodeTable.chordLabel(for: left), "⌃⌥←")
        XCTAssertEqual(KeyCodeTable.meaning(for: left), "Focus column to the left")
        XCTAssertEqual(right.action, .focusRight)
        XCTAssertEqual(left.action, .focusLeft)
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(left)), [.focus(window(1))])
        XCTAssertEqual(WMReducer.reduce(&state, .hotkey(right)), [.focus(window(2))])
        XCTAssertEqual(state.focused, window(2))
    }

    func testMoveWithNoFocusedWindowMovesTheCurrentStripsFocusedColumn() {
        var state = enabled(one: columns(1, 2))
        XCTAssertNil(state.focused)
        let effects = WMReducer.reduce(&state, .hotkey(binding(.moveToWorkspace, "2")))
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(1)])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2)])
        XCTAssertTrue(parks(effects, window(1)))
    }
}
