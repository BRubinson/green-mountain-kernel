import CoreGraphics
import Foundation
import XCTest

/// The accessibility ↔ Cocoa flip round-trips on every side of the primary display.
final class CoordinateSpaceTests: XCTestCase {
    private let primaryHeight: CGFloat = 900

    func testFlipMapsTheTopLeftOfThePrimaryToItsBottomLeftOrigin() {
        let ax = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(
            AxCoordinates.axToCocoa(ax, primaryHeight: primaryHeight),
            CGRect(x: 0, y: 800, width: 100, height: 100)
        )
    }

    func testRoundTripIsTheIdentityOnThePrimaryDisplay() {
        assertRoundTrips(CGRect(x: 120, y: 40, width: 640, height: 480))
    }

    func testRoundTripIsTheIdentityOnADisplayAboveThePrimary() {
        assertRoundTrips(CGRect(x: 200, y: 950, width: 800, height: 600))
    }

    func testRoundTripIsTheIdentityOnADisplayLeftOfThePrimaryWithNegativeX() {
        assertRoundTrips(CGRect(x: -1440, y: 100, width: 1200, height: 700))
    }

    /// Asserts both compositions of the two conversions return `rect` unchanged.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to round-trip.
    ///   - line: The caller's line, for the failure report.
    private func assertRoundTrips(_ rect: CGRect, line: UInt = #line) {
        let cocoa = AxCoordinates.axToCocoa(rect, primaryHeight: primaryHeight)
        XCTAssertEqual(AxCoordinates.cocoaToAx(cocoa, primaryHeight: primaryHeight), rect, line: line)
        let ax = AxCoordinates.cocoaToAx(rect, primaryHeight: primaryHeight)
        XCTAssertEqual(AxCoordinates.axToCocoa(ax, primaryHeight: primaryHeight), rect, line: line)
    }
}
