import CoreGraphics
import Foundation
import XCTest

/// Per-app rules, the heuristic re-test, and floats bound to their workspace.
final class WMReducerRuleTests: XCTestCase {
    private let fixture = WMFixture()
    private let loose = CGRect(x: 100, y: 100, width: 300, height: 300)
    private let app = "com.example.rules"

    /// The window key with CoreGraphics id `id` in the fixture process.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func window(_ id: UInt32) -> WindowKey { fixture.window(id) }

    /// The window key with CoreGraphics id `id` in the ruled app's process, pid 200.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func ruled(_ id: UInt32) -> WindowKey { fixture.window(id, pid: 200) }

    /// Records the ruled app's launch and bundle id.
    ///
    /// - Parameter state: The state to update.
    private func launchRuledApp(_ state: inout WMState) {
        _ = WMReducer.reduce(&state, .appLaunched(pid: 200, launchedAt: fixture.launch, bundleId: app))
    }

    /// The windows of strip `code`, left to right.
    ///
    /// - Parameters:
    ///   - state: The reducer state.
    ///   - code: The workspace code.
    /// - Returns: The tiled windows.
    private func strip(_ state: WMState, _ code: String) -> [WindowKey] {
        state.workspaces[code]?.columns.map(\.window) ?? []
    }

    /// The position of the first effect in `effects` that matches `predicate`.
    ///
    /// - Parameters:
    ///   - effects: Reducer output.
    ///   - predicate: The match.
    /// - Returns: The index, or nil when none matches.
    private func position(_ effects: [WMEffect], _ predicate: (WMEffect) -> Bool) -> Int? {
        effects.firstIndex(where: predicate)
    }

    func testAFloatRuleFloatsANewStandardWindow() {
        var state = fixture.enabled(one: fixture.columns(1))
        launchRuledApp(&state)
        _ = WMReducer.reduce(&state, .rulesReplaced([app: .floating]))
        _ = WMReducer.reduce(&state, .windowCreated(ruled(9), frame: loose, classification: .tiled, title: nil))
        XCTAssertTrue(state.floating.contains(ruled(9)))
        XCTAssertEqual(state.floatWorkspace[ruled(9)], "1")
        XCTAssertEqual(strip(state, "1"), [window(1)])
    }

    func testATileRuleTilesAHeuristicFloat() {
        var state = fixture.enabled(one: fixture.columns(1))
        launchRuledApp(&state)
        _ = WMReducer.reduce(&state, .rulesReplaced([app: .tiled]))
        _ = WMReducer.reduce(&state, .windowCreated(ruled(9), frame: loose, classification: .floating, title: nil))
        XCTAssertEqual(strip(state, "1"), [window(1), ruled(9)])
        XCTAssertFalse(state.floating.contains(ruled(9)))
    }

    func testRulesArriveBeforeEnableAndApply() {
        var state = WMState()
        _ = WMReducer.reduce(&state, .displaysChanged([fixture.main, fixture.side]))
        launchRuledApp(&state)
        XCTAssertEqual(WMReducer.reduce(&state, .rulesReplaced([app: .floating])), [])
        let strips = [WorkspaceStrip(code: "1", displayKey: "main"), WorkspaceStrip(code: "3", displayKey: "side")]
        _ = WMReducer.reduce(&state, .enable(strips: strips, active: ["main": "1", "side": "3"]))
        XCTAssertEqual(state.bundleIds[200], app)
        XCTAssertEqual(state.rules, [app: .floating])
        _ = WMReducer.reduce(&state, .windowCreated(ruled(9), frame: loose, classification: .tiled, title: nil))
        XCTAssertTrue(state.floating.contains(ruled(9)))
    }

    func testReplacingRulesFloatsATiledWindowAndRelayoutsTheStrip() {
        var state = fixture.enabled(one: fixture.columns(1) + [StripColumn(window: ruled(9), weight: 1)])
        launchRuledApp(&state)
        let effects = WMReducer.reduce(&state, .rulesReplaced([app: .floating]))
        XCTAssertTrue(state.floating.contains(ruled(9)))
        XCTAssertEqual(state.floatWorkspace[ruled(9)], "1")
        XCTAssertEqual(strip(state, "1"), [window(1)])
        XCTAssertEqual(fixture.frames(effects)[window(1)], fixture.main.visibleFrame)
        XCTAssertEqual(fixture.raises(effects), [ruled(9)])
        let frame = position(effects) { if case .setFrame = $0 { true } else { false } }
        let raise = position(effects) { $0 == .raise(ruled(9)) }
        XCTAssertLessThan(frame ?? .max, raise ?? -1)
    }

    func testClearingARuleFallsBackToTheHeuristic() {
        var state = fixture.enabled(one: fixture.columns(1))
        launchRuledApp(&state)
        _ = WMReducer.reduce(&state, .rulesReplaced([app: .tiled]))
        _ = WMReducer.reduce(&state, .windowCreated(ruled(9), frame: loose, classification: .floating, title: nil))
        XCTAssertEqual(strip(state, "1"), [window(1), ruled(9)])
        _ = WMReducer.reduce(&state, .rulesReplaced([:]))
        XCTAssertTrue(state.floating.contains(ruled(9)))
        XCTAssertEqual(strip(state, "1"), [window(1)])
    }

    func testReconcilePromotesAFloatThatNowQualifies() {
        var state = fixture.enabled(one: fixture.columns(1))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: loose, classification: .floating, title: nil))
        XCTAssertTrue(state.floating.contains(window(9)))
        let observed = [fixture.observed(1), fixture.observed(9, loose, classification: .tiled)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertEqual(strip(state, "1"), [window(1), window(9)])
        XCTAssertFalse(state.floating.contains(window(9)))
        XCTAssertNil(state.floatWorkspace[window(9)])
    }

    func testReconcileNeverDemotesATileOnHeuristicAlone() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        let observed = [fixture.observed(1), fixture.observed(2, classification: .floating)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
        XCTAssertTrue(state.floating.isEmpty)
        XCTAssertEqual(state.classes[window(2)], .floating)
    }

    func testAPopupIsNeverTracked() {
        var state = fixture.enabled(one: fixture.columns(1))
        let created = WMEvent.windowCreated(window(9), frame: loose, classification: .popup, title: "tip")
        XCTAssertEqual(WMReducer.reduce(&state, created), [])
        XCTAssertFalse(state.knows(window(9)))
        XCTAssertNil(state.frames[window(9)])
        let observed = [fixture.observed(1), fixture.observed(9, loose, classification: .popup)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertFalse(state.knows(window(9)))
    }

    func testAFloatParksAndReturnsWithItsWorkspace() {
        var state = fixture.enabled(one: fixture.columns(1), two: fixture.columns(2))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: loose, classification: .floating, title: nil))
        let away = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "2")))
        XCTAssertTrue(fixture.parks(away, window(9)))
        XCTAssertEqual(state.parked[window(9)], loose)
        XCTAssertEqual(fixture.raises(away), [])
        let back = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "1")))
        XCTAssertTrue(back.contains(.unpark(window(9), loose)))
        XCTAssertNil(state.parked[window(9)])
        XCTAssertEqual(fixture.raises(back), [window(9)])
    }

    func testMovingAFocusedFloatCarriesItToTheTargetWorkspace() {
        var state = fixture.enabled(one: fixture.columns(1), three: fixture.columns(3))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: loose, classification: .floating, title: nil))
        _ = WMReducer.reduce(&state, .windowFocused(window(9)))
        let effects = WMReducer.reduce(&state, .hotkey(fixture.binding(.moveToWorkspace, "3")))
        let carried = CGRect(x: 1100, y: 100, width: 300, height: 300)
        XCTAssertTrue(effects.contains(.setFrame(window(9), carried)))
        XCTAssertEqual(state.floatWorkspace[window(9)], "3")
        XCTAssertEqual(fixture.raises(effects), [window(9)])
        XCTAssertTrue(effects.contains(.focus(window(1))))
        XCTAssertEqual(strip(state, "3"), [window(3)])
        _ = WMReducer.reduce(&state, .windowFocused(window(9)))
        let hidden = WMReducer.reduce(&state, .hotkey(fixture.binding(.moveToWorkspace, "2")))
        XCTAssertTrue(fixture.parks(hidden, window(9)))
        XCTAssertEqual(state.floatWorkspace[window(9)], "2")
        XCTAssertEqual(fixture.raises(hidden), [])
    }

    func testLayoutRaisesTheStripsFloatsAfterTheFocus() {
        var state = fixture.enabled(one: fixture.columns(1), two: fixture.columns(2))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: loose, classification: .floating, title: nil))
        _ = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "2")))
        let effects = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "1")))
        XCTAssertEqual(fixture.raises(effects), [window(9)])
        let raise = position(effects) { $0 == .raise(window(9)) } ?? -1
        let focus = position(effects) { $0 == .focus(window(1)) } ?? .max
        XCTAssertLessThan(focus, raise)
        for (index, effect) in effects.enumerated() {
            switch effect {
            case .setFrame, .park, .unpark: XCTAssertLessThan(index, raise, "\(effect)")
            default: break
            }
        }
        guard case .mirrorDirty? = effects.last else { return XCTFail("no trailing mirrorDirty") }
    }

    func testARaiseIsDroppedForAWindowThatEndsParked() {
        let parkRect = CGRect(x: 999, y: 779, width: 300, height: 300)
        let parked = WMReducer.coalesce([.raise(window(9)), .park(window(9), parkRect)])
        XCTAssertEqual(
            parked,
            [.park(window(9), parkRect), .mirrorDirty(windows: [window(9)], processes: [], urgent: true)]
        )
        let shown = WMReducer.coalesce([.raise(window(9)), .unpark(window(9), loose), .raise(window(9))])
        XCTAssertEqual(
            shown,
            [
                .unpark(window(9), loose), .raise(window(9)),
                .mirrorDirty(windows: [window(9)], processes: [], urgent: true),
            ]
        )
    }

    func testMovingAFloatAcrossDisplaysRebindsIt() {
        var state = fixture.enabled(one: fixture.columns(1), three: fixture.columns(3))
        _ = WMReducer.reduce(&state, .windowCreated(window(9), frame: loose, classification: .floating, title: nil))
        XCTAssertEqual(state.floatWorkspace[window(9)], "1")
        _ = WMReducer.reduce(&state, .windowMoved(window(9), CGRect(x: 1100, y: 100, width: 300, height: 300)))
        XCTAssertEqual(state.floatWorkspace[window(9)], "3")
        _ = WMReducer.reduce(&state, .mousePressed(at: CGPoint(x: 1200, y: 390)))
        _ = WMReducer.reduce(&state, .windowMoved(window(9), loose))
        XCTAssertEqual(state.floatWorkspace[window(9)], "3")
        let released = WMReducer.reduce(&state, .mouseReleased(at: CGPoint(x: 250, y: 390)))
        XCTAssertEqual(state.floatWorkspace[window(9)], "1")
        XCTAssertEqual(released.last, .mirrorDirty(windows: [window(9)], processes: [], urgent: false))
    }
}
