import CoreGraphics
import Foundation
import XCTest

/// Weighted column arithmetic: frames, appends, resizes, focus and slide.
final class ColumnLayoutTests: XCTestCase {
    /// A 1000pt-wide visible frame.
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 500)
    /// A 900pt-wide visible frame, 300pt per column at equal weights.
    private let visible3 = CGRect(x: 0, y: 0, width: 900, height: 500)

    func testEqualWeightsGiveEqualWidths() {
        let frames = ColumnLayout.frames(weights: [1, 1, 1], visible: CGRect(x: 0, y: 20, width: 900, height: 500))
        XCTAssertEqual(frames.map(\.width), [300, 300, 300])
        XCTAssertEqual(frames.map(\.minX), [0, 300, 600])
        XCTAssertTrue(frames.allSatisfy { $0.minY == 20 && $0.height == 500 })
    }

    func testWidthsSumExactlyToAnOddVisibleWidth() {
        let visible = CGRect(x: 10, y: 0, width: 1001, height: 500)
        let frames = ColumnLayout.frames(weights: [1, 1, 1], visible: visible)
        XCTAssertEqual(frames.map(\.width).reduce(0, +), 1001)
        XCTAssertEqual(frames.first?.minX, visible.minX)
        XCTAssertEqual(frames.last?.maxX, visible.maxX)
        for (left, right) in zip(frames, frames.dropFirst()) { XCTAssertEqual(left.maxX, right.minX) }
        XCTAssertTrue(ColumnLayout.frames(weights: [], visible: visible).isEmpty)
    }

    func testAppendWeightIsTheMean() {
        XCTAssertEqual(ColumnLayout.appendWeight(existing: [1, 2, 3]), 2)
        XCTAssertEqual(ColumnLayout.appendWeight(existing: []), 1)
    }

    func testRightEdgeDragTradesWithTheRightNeighbour() {
        let observed = CGRect(x: 0, y: 0, width: 600, height: 500)
        assertWeights(
            ColumnLayout.redistribute(weights: [1, 1], index: 0, observed: observed, visible: visible),
            [1.2, 0.8]
        )
    }

    func testLeftEdgeDragTradesWithTheLeftNeighbour() {
        let observed = CGRect(x: 400, y: 0, width: 600, height: 500)
        assertWeights(
            ColumnLayout.redistribute(weights: [1, 1], index: 1, observed: observed, visible: visible),
            [0.8, 1.2]
        )
        let middle = CGRect(x: 200, y: 0, width: 400, height: 500)
        let three = ColumnLayout.redistribute(weights: [1, 1, 1], index: 1, observed: middle, visible: visible3)
        assertWeights(three, [2.0 / 3, 4.0 / 3, 1])
    }

    func testOuterEdgeDragChangesNothing() {
        let observed = CGRect(x: -100, y: 0, width: 600, height: 500)
        XCTAssertEqual(
            ColumnLayout.redistribute(weights: [1, 1], index: 0, observed: observed, visible: visible),
            [1, 1]
        )
    }

    func testRedistributeClampsTheNeighbourToTheMinimumWidth() {
        let observed = CGRect(x: 0, y: 0, width: 950, height: 500)
        assertWeights(
            ColumnLayout.redistribute(weights: [1, 1], index: 0, observed: observed, visible: visible),
            [1.8, 0.2]
        )
    }

    func testResizeStepMovesFiftyPointsAndConservesTheSum() {
        let grown = ColumnLayout.resizeStep(weights: [1, 1, 1], index: 1, deltaPoints: 50, visibleWidth: 900)
        assertWeights(grown, [1, 1 + 50.0 / 300, 1 - 50.0 / 300])
        let shrunk = ColumnLayout.resizeStep(weights: [1, 1], index: 0, deltaPoints: -50, visibleWidth: 1000)
        assertWeights(shrunk, [0.9, 1.1])
        XCTAssertEqual(ColumnLayout.resizeStep(weights: [1], index: 0, deltaPoints: 50, visibleWidth: 1000), [1])
    }

    func testFocusIndexClampsWithoutWrapping() {
        XCTAssertEqual(ColumnLayout.focusIndex(from: 0, delta: -1, count: 3), 0)
        XCTAssertEqual(ColumnLayout.focusIndex(from: 2, delta: 1, count: 3), 2)
        XCTAssertEqual(ColumnLayout.focusIndex(from: 1, delta: 1, count: 3), 2)
        XCTAssertEqual(ColumnLayout.focusIndex(from: nil, delta: 1, count: 3), 0)
        XCTAssertNil(ColumnLayout.focusIndex(from: 0, delta: 1, count: 0))
    }

    func testSlideSwapsWithTheNeighbourAndStopsAtTheEnds() {
        let (right, rightIndex) = ColumnLayout.slide(order: ["a", "b", "c"], index: 0, delta: 1)
        XCTAssertEqual(right, ["b", "a", "c"])
        XCTAssertEqual(rightIndex, 1)
        let (left, leftIndex) = ColumnLayout.slide(order: ["a", "b", "c"], index: 0, delta: -1)
        XCTAssertEqual(left, ["a", "b", "c"])
        XCTAssertEqual(leftIndex, 0)
        let (end, endIndex) = ColumnLayout.slide(order: ["a", "b", "c"], index: 2, delta: 1)
        XCTAssertEqual(end, ["a", "b", "c"])
        XCTAssertEqual(endIndex, 2)
    }

    func testRemoveRenormalizesToAMeanOfOne() {
        assertWeights(ColumnLayout.remove(weights: [1, 2, 3], at: 1), [0.5, 1.5])
        XCTAssertEqual(ColumnLayout.remove(weights: [4], at: 0), [])
    }

    /// Asserts two weight lists are equal element by element within `1e-9`.
    ///
    /// - Parameters:
    ///   - actual: The computed weights.
    ///   - expected: The expected weights.
    ///   - line: The caller's line, for the failure report.
    private func assertWeights(_ actual: [Double], _ expected: [Double], line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, line: line)
        for (lhs, rhs) in zip(actual, expected) { XCTAssertEqual(lhs, rhs, accuracy: 1e-9, line: line) }
    }
}
