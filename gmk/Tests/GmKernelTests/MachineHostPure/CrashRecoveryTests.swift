import CoreGraphics
import Foundation
import XCTest

/// Geometric-first crash recovery against a mirror that may be empty, stale or right.
final class CrashRecoveryTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_700_000_000)
    private let main = DisplayGeom(
        key: "main",
        frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 780),
        isMain: true
    )
    private let size = CGSize(width: 400, height: 300)

    /// The fixture window with id 1, launched at `launchedAt`.
    ///
    /// - Parameter launchedAt: The owning process's launch date.
    /// - Returns: The key.
    private func key(launchedAt: Date) -> WindowKey {
        WindowKey(pid: 42, launchedAt: launchedAt, cgWindowId: 1)
    }

    /// The window observed parked at the bottom-right corner of the main display.
    private var parkedWindow: ObservedWindow {
        let frame = ParkGeometry.parkRect(windowSize: size, display: main, corner: .bottomRight)
        return ObservedWindow(key: key(launchedAt: launch), frame: frame, classification: .tiled, title: nil)
    }

    /// The frame a window of the fixture size is centred to.
    private var centred: CGRect { CGRect(x: 300, y: 240, width: 400, height: 300) }

    func testParkedWindowWithMirrorPreParkReturnsThere() {
        let prePark = CGRect(x: 50, y: 60, width: 400, height: 300)
        let mirror = [MirrorWindowSnapshot(pid: 42, launchedAt: launch, cgWindowId: 1, prePark: prePark)]
        let moves = CrashRecovery.plan(observed: [parkedWindow], displays: [main], mirror: mirror)
        XCTAssertEqual(moves.map(\.0), [key(launchedAt: launch)])
        XCTAssertEqual(moves.map(\.1), [prePark])
    }

    func testParkedWindowWithNoMirrorRowIsCentredOnTheMainDisplay() {
        let moves = CrashRecovery.plan(observed: [parkedWindow], displays: [main], mirror: [])
        XCTAssertEqual(moves.map(\.1), [centred])
    }

    func testMirrorRowWithAnotherLaunchDateIsIgnored() {
        let stale = MirrorWindowSnapshot(
            pid: 42,
            launchedAt: launch.addingTimeInterval(-3600),
            cgWindowId: 1,
            prePark: CGRect(x: 50, y: 60, width: 400, height: 300)
        )
        let moves = CrashRecovery.plan(observed: [parkedWindow], displays: [main], mirror: [stale])
        XCTAssertEqual(moves.map(\.1), [centred])
    }

    func testPreParkFrameThatIsItselfOffScreenFallsBackToCentring() {
        let offScreen = CGRect(x: 4000, y: 4000, width: 400, height: 300)
        let mirror = [MirrorWindowSnapshot(pid: 42, launchedAt: launch, cgWindowId: 1, prePark: offScreen)]
        let moves = CrashRecovery.plan(observed: [parkedWindow], displays: [main], mirror: mirror)
        XCTAssertEqual(moves.map(\.1), [centred])
    }

    func testVisibleWindowIsNeverMoved() {
        let visible = ObservedWindow(
            key: key(launchedAt: launch),
            frame: CGRect(x: 100, y: 100, width: 400, height: 300),
            classification: .tiled,
            title: nil
        )
        XCTAssertTrue(CrashRecovery.plan(observed: [visible], displays: [main], mirror: []).isEmpty)
    }

    func testOversizedWindowIsClampedToTheVisibleFrame() {
        XCTAssertEqual(
            CrashRecovery.centred(size: CGSize(width: 3000, height: 3000), in: main.visibleFrame),
            main.visibleFrame
        )
    }
}
