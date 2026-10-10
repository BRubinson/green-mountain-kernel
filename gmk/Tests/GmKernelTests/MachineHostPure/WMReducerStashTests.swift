import CoreGraphics
import Foundation
import XCTest

/// Minimized and hidden windows leave the layout and return to where they were.
final class WMReducerStashTests: XCTestCase {
    private let fixture = WMFixture()
    private let loose = CGRect(x: 100, y: 100, width: 300, height: 300)

    /// The window key with CoreGraphics id `id` in the fixture process.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func window(_ id: UInt32) -> WindowKey { fixture.window(id) }

    /// The windows of strip `code`, left to right.
    ///
    /// - Parameters:
    ///   - state: The reducer state.
    ///   - code: The workspace code.
    /// - Returns: The tiled windows.
    private func strip(_ state: WMState, _ code: String) -> [WindowKey] {
        state.workspaces[code]?.columns.map(\.window) ?? []
    }

    func testMinimizingATiledWindowClosesItsGap() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        let effects = WMReducer.reduce(&state, .windowMinimized(window(2)))
        XCTAssertEqual(strip(state, "1"), [window(1), window(3)])
        XCTAssertEqual(state.stashed[window(2)]?.reason, .minimized)
        XCTAssertEqual(state.stashed[window(2)]?.kind, .tiled)
        XCTAssertEqual(state.stashed[window(2)]?.index, 1)
        XCTAssertEqual(state.stashed[window(2)]?.workspaceCode, "1")
        XCTAssertEqual(fixture.frames(effects)[window(1)], CGRect(x: 0, y: 0, width: 500, height: 780))
        XCTAssertEqual(fixture.frames(effects)[window(3)], CGRect(x: 500, y: 0, width: 500, height: 780))
        XCTAssertNil(fixture.frames(effects)[window(2)])
    }

    func testDeminimizingRestoresItsSlotAndWeight() {
        let one = [
            StripColumn(window: window(1), weight: 1),
            StripColumn(window: window(2), weight: 1.5),
            StripColumn(window: window(3), weight: 0.5),
        ]
        var state = fixture.enabled(one: one)
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        let effects = WMReducer.reduce(&state, .windowDeminimized(window(2), frame: loose, classification: .tiled))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2), window(3)])
        let weights = state.workspaces["1"]?.weights ?? []
        for (weight, expected) in zip(weights, [1, 1.5, 0.5]) { XCTAssertEqual(weight, expected, accuracy: 1e-9) }
        XCTAssertTrue(state.stashed.isEmpty)
        XCTAssertEqual(fixture.frames(effects)[window(2)]?.width ?? 0, 500, accuracy: 1)
    }

    func testDeminimizingIntoAShrunkStripClampsTheIndex() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowMinimized(window(3)))
        _ = WMReducer.reduce(&state, .windowDestroyed(window(2)))
        _ = WMReducer.reduce(&state, .windowDeminimized(window(3), frame: loose, classification: .tiled))
        XCTAssertEqual(strip(state, "1"), [window(1), window(3)])
    }

    func testAMinimizedFloatReturnsAsAFloat() {
        var state = fixture.enabled(one: fixture.columns(1))
        _ = WMReducer.reduce(&state, .windowCreated(window(7), frame: loose, classification: .floating, title: nil))
        _ = WMReducer.reduce(&state, .windowMinimized(window(7)))
        XCTAssertFalse(state.floating.contains(window(7)))
        XCTAssertEqual(state.stashed[window(7)]?.kind, .floating)
        _ = WMReducer.reduce(&state, .windowDeminimized(window(7), frame: loose, classification: .floating))
        XCTAssertTrue(state.floating.contains(window(7)))
        XCTAssertEqual(state.floatWorkspace[window(7)], "1")
        XCTAssertEqual(strip(state, "1"), [window(1)])
    }

    func testAWindowFirstSeenMinimizedIsClassifiedOnRestore() {
        var state = fixture.enabled(one: fixture.columns(1))
        let created = WMEvent.windowCreated(
            window(7),
            frame: loose,
            classification: .floating,
            title: nil,
            isMinimized: true
        )
        XCTAssertEqual(fixture.frames(WMReducer.reduce(&state, created)), [:])
        XCTAssertNil(state.stashed[window(7)]?.kind)
        XCTAssertEqual(state.stashed[window(7)]?.workspaceCode, "1")
        _ = WMReducer.reduce(&state, .windowDeminimized(window(7), frame: loose, classification: .tiled))
        XCTAssertEqual(strip(state, "1"), [window(1), window(7)])
    }

    func testReconcileHonoursAXMinimizedWhenTheNotificationWasMissed() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        let observed = [fixture.observed(1), fixture.observed(2, minimized: true)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertEqual(strip(state, "1"), [window(1)])
        XCTAssertEqual(state.stashed[window(2)]?.reason, .minimized)
    }

    func testReconcileRestoresWhenAXMinimizedClears() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        let observed = [fixture.observed(1), fixture.observed(2)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
        XCTAssertTrue(state.stashed.isEmpty)
    }

    func testHidingAnAppStashesEveryWindowAndUnhidingRestoresThem() {
        let other = fixture.window(9, pid: 200)
        var state = fixture.enabled(one: fixture.columns(1, 2) + [StripColumn(window: other, weight: 1)])
        _ = WMReducer.reduce(&state, .windowCreated(window(7), frame: loose, classification: .floating, title: nil))
        _ = WMReducer.reduce(&state, .appHidden(pid: 100))
        XCTAssertEqual(strip(state, "1"), [other])
        XCTAssertEqual(Set(state.stashed.keys), [window(1), window(2), window(7)])
        XCTAssertTrue(state.stashed.values.allSatisfy { $0.reason == .hidden })
        XCTAssertTrue(state.floating.isEmpty)
        _ = WMReducer.reduce(&state, .appUnhidden(pid: 100))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2), other])
        XCTAssertEqual(state.floating, [window(7)])
        XCTAssertTrue(state.stashed.isEmpty)
    }

    func testReconcileHiddenSetStashesAndRestores() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        let observed = [fixture.observed(1), fixture.observed(2)]
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100], hidden: [100]))
        XCTAssertEqual(strip(state, "1"), [])
        XCTAssertEqual(Set(state.stashed.keys), [window(1), window(2)])
        _ = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100], hidden: []))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
        XCTAssertTrue(state.stashed.isEmpty)
    }

    func testAMinimizedWindowStaysStashedThroughHideAndUnhide() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        _ = WMReducer.reduce(&state, .appHidden(pid: 100))
        XCTAssertEqual(state.stashed[window(1)]?.reason, .hidden)
        XCTAssertEqual(state.stashed[window(2)]?.reason, .minimized)
        _ = WMReducer.reduce(&state, .appUnhidden(pid: 100))
        XCTAssertEqual(strip(state, "1"), [window(1)])
        XCTAssertEqual(state.stashed[window(2)]?.reason, .minimized)
    }

    func testClosingAMinimizedWindowForgetsIt() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        _ = WMReducer.reduce(&state, .reconcile(observed: [fixture.observed(1)], answered: [100]))
        XCTAssertTrue(state.stashed.isEmpty)
        XCTAssertFalse(state.knows(window(2)))
        XCTAssertEqual(strip(state, "1"), [window(1)])
    }

    func testAReconcileRestoreIntoAHiddenWorkspaceParks() {
        var state = fixture.enabled(one: fixture.columns(1, 2), two: fixture.columns(5))
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        _ = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "2")))
        let observed = [fixture.observed(1), fixture.observed(2, loose), fixture.observed(5)]
        let effects = WMReducer.reduce(&state, .reconcile(observed: observed, answered: [100]))
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
        XCTAssertEqual(state.activeByDisplay["main"], "2")
        XCTAssertTrue(fixture.parks(effects, window(2)))
        XCTAssertEqual(state.parked[window(2)], loose)
        XCTAssertNil(fixture.frames(effects)[window(1)])
    }

    func testDeminimizingAfterItsFocusEventShowsTheHiddenWorkspace() {
        var state = fixture.enabled(one: fixture.columns(1, 2), two: fixture.columns(5))
        _ = WMReducer.reduce(&state, .windowMinimized(window(2)))
        _ = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "2")))
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        let effects = WMReducer.reduce(&state, .windowDeminimized(window(2), frame: loose, classification: .tiled))
        XCTAssertEqual(state.activeByDisplay["main"], "1")
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
        XCTAssertFalse(fixture.parks(effects, window(2)))
        XCTAssertNil(state.parked[window(2)])
        XCTAssertEqual(fixture.frames(effects)[window(2)], CGRect(x: 500, y: 0, width: 500, height: 780))
        XCTAssertEqual(fixture.frames(effects)[window(1)], CGRect(x: 0, y: 0, width: 500, height: 780))
        XCTAssertTrue(fixture.parks(effects, window(5)))
        XCTAssertEqual(state.focused, window(2))
        XCTAssertTrue(effects.contains(.focus(window(2))))
    }

    func testDeminimizingAFloatOfAHiddenWorkspaceShowsItAndFocusesTheFloat() {
        var state = fixture.enabled(one: fixture.columns(1), two: fixture.columns(5))
        _ = WMReducer.reduce(&state, .windowCreated(window(7), frame: loose, classification: .floating, title: nil))
        _ = WMReducer.reduce(&state, .windowMinimized(window(7)))
        _ = WMReducer.reduce(&state, .hotkey(fixture.binding(.focusWorkspace, "2")))
        let effects = WMReducer.reduce(&state, .windowDeminimized(window(7), frame: loose, classification: .floating))
        XCTAssertEqual(state.activeByDisplay["main"], "1")
        XCTAssertEqual(state.floatWorkspace[window(7)], "1")
        XCTAssertFalse(fixture.parks(effects, window(7)))
        XCTAssertEqual(state.focused, window(7))
        XCTAssertEqual(effects.last { if case .focus = $0 { true } else { false } }, .focus(window(7)))
    }

    func testAWindowFirstSeenWhileHiddenWaitsForAFreshVerdict() {
        var state = fixture.enabled(one: fixture.columns(1))
        let late = fixture.window(7, pid: 200)
        let whileHidden = ObservedWindow(
            key: late,
            frame: loose,
            classification: .floating,
            title: nil,
            isMinimized: false
        )
        let hidden = WMEvent.reconcile(
            observed: [fixture.observed(1), whileHidden],
            answered: [100, 200],
            hidden: [200]
        )
        _ = WMReducer.reduce(&state, hidden)
        XCTAssertEqual(state.stashed[late]?.reason, .hidden)
        XCTAssertNil(state.classes[late])
        _ = WMReducer.reduce(&state, .appUnhidden(pid: 200))
        XCTAssertNotNil(state.stashed[late])
        XCTAssertFalse(state.floating.contains(late))
        let shown = ObservedWindow(key: late, frame: loose, classification: .tiled, title: nil, isMinimized: false)
        _ = WMReducer.reduce(&state, .reconcile(observed: [fixture.observed(1), shown], answered: [100, 200]))
        XCTAssertEqual(strip(state, "1"), [window(1), late])
        XCTAssertFalse(state.floating.contains(late))
        XCTAssertTrue(state.stashed.isEmpty)
    }

    func testAnUnreadableWindowIsNotDestroyed() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        let reconcile = WMEvent.reconcile(
            observed: [fixture.observed(1)],
            answered: [100],
            hidden: [],
            unreadable: [window(2)]
        )
        _ = WMReducer.reduce(&state, reconcile)
        XCTAssertEqual(strip(state, "1"), [window(1), window(2)])
    }
}
