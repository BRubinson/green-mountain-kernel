import CoreGraphics
import Foundation
import XCTest

/// Which window a move takes and where focus lands after it.
final class WMReducerFocusTests: XCTestCase {
    private let fixture = WMFixture()

    /// The window key with CoreGraphics id `id` in the fixture process.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func window(_ id: UInt32) -> WindowKey { fixture.window(id) }

    /// Runs the move-to-workspace hotkey for `code`.
    ///
    /// - Parameters:
    ///   - state: The state to update.
    ///   - code: The target workspace.
    /// - Returns: The effects.
    private func move(_ state: inout WMState, to code: String) -> [WMEffect] {
        WMReducer.reduce(&state, .hotkey(fixture.binding(.moveToWorkspace, code)))
    }

    func testMoveAfterFocusingAnUntrackedWindowIsANoOp() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        XCTAssertEqual(WMReducer.reduce(&state, .windowFocused(window(99))), [])
        XCTAssertNil(state.focused)
        XCTAssertTrue(state.focusUnmanaged)
        XCTAssertEqual(move(&state, to: "2"), [])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
        XCTAssertEqual(state.workspaces["2"]?.columns, [])
    }

    func testFocusUnmanagedMakesAMoveANoOp() {
        var state = fixture.enabled(one: fixture.columns(1, 2))
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        XCTAssertEqual(WMReducer.reduce(&state, .focusUnmanaged), [])
        XCTAssertNil(state.focused)
        XCTAssertEqual(move(&state, to: "2"), [])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(2)])
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        XCTAssertFalse(state.focusUnmanaged)
        _ = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(2)])
    }

    func testMoveTakesTheNativelyFocusedWindowNotTheCachedOne() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(3)))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        let effects = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(1)])
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(3)])
        XCTAssertEqual(state.focused, window(2))
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 0)
        XCTAssertTrue(effects.contains(.focus(window(2))))
    }

    func testFocusLandsOnTheLeftNeighbourAfterAMove() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        let effects = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1), window(3)])
        XCTAssertEqual(state.focused, window(1))
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 0)
        XCTAssertTrue(effects.contains(.focus(window(1))))
        XCTAssertFalse(effects.contains(.focus(window(3))))
    }

    func testFocusAfterMovingTheLeftmostColumnLandsOnTheNewLeftmost() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        let effects = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(2), window(3)])
        XCTAssertEqual(state.focused, window(2))
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 0)
        XCTAssertTrue(effects.contains(.focus(window(2))))
    }

    func testMovingTheLastColumnLeavesNoFocus() {
        var state = fixture.enabled(one: fixture.columns(1))
        _ = WMReducer.reduce(&state, .windowFocused(window(1)))
        let effects = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["1"]?.columns, [])
        XCTAssertNil(state.workspaces["1"]?.focusedIndex)
        XCTAssertNil(state.focused)
        XCTAssertFalse(effects.contains { if case .focus = $0 { true } else { false } })
    }

    func testRepeatedMovesWalkLeftward() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3, 4))
        _ = WMReducer.reduce(&state, .windowFocused(window(4)))
        for (moved, next) in [(4, 3), (3, 2), (2, 1)] as [(UInt32, UInt32)] {
            let effects = move(&state, to: "2")
            XCTAssertEqual(state.workspaces["2"]?.columns.last?.window, window(moved))
            XCTAssertEqual(state.focused, window(next), "after moving \(moved)")
            XCTAssertEqual(state.workspaces["1"]?.focusedIndex, Int(next) - 1)
            XCTAssertTrue(effects.contains(.focus(window(next))))
        }
        XCTAssertEqual(state.workspaces["1"]?.columns.map(\.window), [window(1)])
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(4), window(3), window(2)])
    }

    func testClosingTheFocusedColumnKeepsTheLeftNeighbourFocused() {
        var state = fixture.enabled(one: fixture.columns(1, 2, 3))
        _ = WMReducer.reduce(&state, .windowFocused(window(2)))
        _ = WMReducer.reduce(&state, .windowDestroyed(window(2)))
        XCTAssertNil(state.focused)
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 0)
        let effects = move(&state, to: "2")
        XCTAssertEqual(state.workspaces["2"]?.columns.map(\.window), [window(1)])
        XCTAssertEqual(state.focused, window(3))
        XCTAssertEqual(state.workspaces["1"]?.focusedIndex, 0)
        XCTAssertTrue(effects.contains(.focus(window(3))))
    }
}
