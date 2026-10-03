import CoreGraphics
import Foundation
import XCTest

/// The per-display park corner, the 1pt sliver, and the hidden-window predicate.
final class ParkGeometryTests: XCTestCase {
    /// A display whose visible frame is its frame minus a 25pt menu bar on top.
    ///
    /// - Parameters:
    ///   - key: The display key.
    ///   - x: The frame's left edge.
    ///   - y: The frame's bottom edge.
    ///   - isMain: Whether it is the main display.
    /// - Returns: A 1000 × 800 display.
    private func display(_ key: String, x: CGFloat, y: CGFloat, isMain: Bool = false) -> DisplayGeom {
        DisplayGeom(
            key: key,
            frame: CGRect(x: x, y: y, width: 1000, height: 800),
            visibleFrame: CGRect(x: x, y: y, width: 1000, height: 775),
            isMain: isMain
        )
    }

    /// The four arrangements every assertion runs over.
    private var arrangements: [[DisplayGeom]] {
        [
            [display("solo", x: 0, y: 0, isMain: true)],
            [display("left", x: 0, y: 0, isMain: true), display("right", x: 1000, y: 0)],
            [display("bottom", x: 0, y: 0, isMain: true), display("top", x: 0, y: 800)],
            [display("a", x: 0, y: 0, isMain: true), display("b", x: 1000, y: 0), display("c", x: 0, y: 800)],
        ]
    }

    func testAParkedWindowShowsAtMostAOnePointSliverOnAnotherDisplay() {
        for displays in arrangements {
            for target in displays {
                let corner = ParkGeometry.parkCorner(for: target, among: displays)
                let rect = ParkGeometry.parkRect(windowSize: target.frame.size, display: target, corner: corner)
                for other in displays where other.key != target.key {
                    let overlap = rect.intersection(other.frame)
                    XCTAssertTrue(
                        overlap.isNull || min(overlap.width, overlap.height) <= 1,
                        "\(target.key) parks \(corner) onto \(other.key)"
                    )
                }
            }
        }
    }

    func testOnlyBottomCornersAreChosenAndTheLeastOverlappingWins() {
        XCTAssertEqual(ParkGeometry.Corner.allCases, [.bottomRight, .bottomLeft])
        let stacked = arrangements[2]
        XCTAssertEqual(ParkGeometry.parkCorner(for: stacked[0], among: stacked), .bottomRight)
        XCTAssertEqual(ParkGeometry.parkCorner(for: stacked[1], among: stacked), .bottomRight)
        let sideBySide = arrangements[1]
        XCTAssertEqual(ParkGeometry.parkCorner(for: sideBySide[0], among: sideBySide), .bottomLeft)
        XCTAssertEqual(ParkGeometry.parkCorner(for: sideBySide[1], among: sideBySide), .bottomRight)
        let lShape = arrangements[3]
        XCTAssertEqual(ParkGeometry.parkCorner(for: lShape[0], among: lShape), .bottomLeft)
        XCTAssertEqual(ParkGeometry.parkCorner(for: lShape[2], among: lShape), .bottomLeft)
    }

    func testTheUpperOfTwoStackedDisplaysParksBelowItsOwnVisibleFrame() {
        let stacked = arrangements[2]
        let upper = stacked[1]
        let corner = ParkGeometry.parkCorner(for: upper, among: stacked)
        let rect = ParkGeometry.parkRect(windowSize: CGSize(width: 700, height: 500), display: upper, corner: corner)
        XCTAssertLessThanOrEqual(rect.maxY, upper.visibleFrame.minY + 1)
        XCTAssertTrue(ParkGeometry.isParked(frame: rect, displays: stacked))
    }

    func testParkRectLeavesExactlyAOnePointSliver() {
        let size = CGSize(width: 700, height: 500)
        for displays in arrangements {
            for target in displays {
                for corner in ParkGeometry.Corner.allCases {
                    let rect = ParkGeometry.parkRect(windowSize: size, display: target, corner: corner)
                    let sliver = rect.intersection(target.visibleFrame)
                    XCTAssertEqual(sliver.size, CGSize(width: 1, height: 1), "\(target.key) \(corner)")
                    XCTAssertEqual(rect.size, size)
                }
            }
        }
    }

    func testIsParkedHoldsForParkedRectsAndNotForTiledFrames() {
        for displays in arrangements {
            for target in displays {
                let corner = ParkGeometry.parkCorner(for: target, among: displays)
                let size = CGSize(width: 700, height: 500)
                let parked = ParkGeometry.parkRect(windowSize: size, display: target, corner: corner)
                XCTAssertTrue(ParkGeometry.isParked(frame: parked, displays: displays))
                XCTAssertFalse(ParkGeometry.isParked(frame: target.visibleFrame, displays: displays))
                let half = CGRect(x: target.visibleFrame.minX, y: target.visibleFrame.minY, width: 500, height: 775)
                XCTAssertFalse(ParkGeometry.isParked(frame: half, displays: displays))
            }
        }
    }

    func testAWindowEntirelyOffScreenCountsAsHidden() {
        let lost = CGRect(x: 5000, y: 5000, width: 300, height: 300)
        XCTAssertTrue(ParkGeometry.isParked(frame: lost, displays: arrangements[0]))
    }
}
