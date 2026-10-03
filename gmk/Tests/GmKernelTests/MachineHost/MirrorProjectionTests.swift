import CoreGraphics
import Foundation
import XCTest

/// The mirror diff writes only material changes.
final class MirrorProjectionTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_700_000_000)

    /// The fixture process.
    private var process: ProcessKey { ProcessKey(pid: 7, launchedAt: launch) }

    /// A window of the fixture process.
    ///
    /// - Parameter id: The window id.
    /// - Returns: The key.
    private func window(_ id: UInt32) -> WindowKey {
        WindowKey(pid: 7, launchedAt: launch, cgWindowId: id)
    }

    /// An image with the fixture process and two tiled windows.
    private var base: MirrorImage {
        let value = MirrorWindow(
            workspaceCode: "1",
            columnIndex: 0,
            weight: 1,
            floating: false,
            frame: CGRect(x: 0, y: 0, width: 500, height: 780),
            prePark: nil,
            title: "one"
        )
        var second = value
        second.columnIndex = 1
        second.frame = CGRect(x: 500, y: 0, width: 500, height: 780)
        return MirrorImage(
            windows: [window(1): value, window(2): second],
            processes: [process: MirrorProcess(bundleId: "com.example.app", name: "Example", running: true)]
        )
    }

    func testIdenticalImagesGiveAnEmptyDelta() {
        XCTAssertTrue(MirrorProjection.diff(last: base, current: base).isEmpty)
    }

    func testOnePointOfJitterAndATitleChangeGiveAnEmptyDelta() {
        var current = base
        current.windows[window(1)]?.frame = CGRect(x: 1, y: 0.5, width: 499, height: 780)
        current.windows[window(2)]?.title = "renamed"
        XCTAssertTrue(MirrorProjection.diff(last: base, current: current).isEmpty)
    }

    func testAWeightChangeGivesExactlyOneWindowUpsert() {
        var current = base
        current.windows[window(1)]?.weight = 1.2
        let delta = MirrorProjection.diff(last: base, current: current)
        XCTAssertEqual(Array(delta.windowUpserts.keys), [window(1)])
        XCTAssertTrue(delta.windowRetirements.isEmpty && delta.processUpserts.isEmpty)
    }

    func testAClosedWindowGivesOneRetirement() {
        var current = base
        current.windows[window(2)] = nil
        let delta = MirrorProjection.diff(last: base, current: current)
        XCTAssertEqual(delta.windowRetirements, [window(2)])
        XCTAssertTrue(delta.windowUpserts.isEmpty)
    }

    func testATerminatedProcessRetiresTheProcessAndItsWindows() {
        let delta = MirrorProjection.diff(last: base, current: MirrorImage())
        XCTAssertEqual(delta.processRetirements, [process])
        XCTAssertEqual(delta.windowRetirements, [window(1), window(2)])
        XCTAssertEqual(base.applying(delta), MirrorImage())
    }

    func testSettingAPreParkFrameAppearsInTheUpsert() {
        var current = base
        let prePark = CGRect(x: 0, y: 0, width: 500, height: 780)
        current.windows[window(1)]?.prePark = prePark
        let delta = MirrorProjection.diff(last: base, current: current)
        XCTAssertEqual(delta.windowUpserts[window(1)]?.prePark, prePark)
        XCTAssertEqual(base.applying(delta), current)
    }
}
