import Foundation
import XCTest

/// The tile-or-float predicate.
final class WindowClassifierTests: XCTestCase {
    func testAStandardWindowTiles() {
        let result = WindowClassifier.classify(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isMinimized: false,
            isFullscreen: false
        )
        XCTAssertEqual(result, .tiled)
    }

    func testDialogsMinimizedFullscreenAndUnknownRolesFloat() {
        let cases: [(String?, String?, Bool, Bool)] = [
            ("AXWindow", "AXDialog", false, false),
            ("AXWindow", "AXStandardWindow", true, false),
            ("AXWindow", "AXStandardWindow", false, true),
            (nil, "AXStandardWindow", false, false),
            ("AXWindow", nil, false, false),
        ]
        for (role, subrole, isMinimized, isFullscreen) in cases {
            let result = WindowClassifier.classify(
                role: role,
                subrole: subrole,
                isMinimized: isMinimized,
                isFullscreen: isFullscreen
            )
            XCTAssertEqual(result, .floating, "\(String(describing: role)) \(String(describing: subrole))")
        }
    }
}
