import Foundation
import XCTest

/// The window, dialog and popup heuristic.
final class WindowClassifierTests: XCTestCase {
    /// The facts of a standard window with every title-bar button, which tiles.
    private var standard: WindowFacts {
        WindowFacts(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "Document",
            hasCloseButton: true,
            hasZoomButton: true,
            hasMinimizeButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            bundleId: "com.example.app"
        )
    }

    func testAStandardWindowWithAnEnabledFullscreenButtonTiles() {
        XCTAssertEqual(WindowClassifier.classify(standard), .tiled)
    }

    func testAStandardWindowWithoutAFullscreenButtonFloats() {
        var facts = standard
        facts.hasFullscreenButton = false
        facts.fullscreenButtonEnabled = false
        XCTAssertEqual(WindowClassifier.classify(facts), .floating)
        facts.hasFullscreenButton = true
        XCTAssertEqual(WindowClassifier.classify(facts), .floating)
    }

    func testAnExemptBundleTilesWithoutAFullscreenButton() {
        var facts = standard
        facts.hasFullscreenButton = false
        facts.fullscreenButtonEnabled = false
        facts.bundleId = "org.alacritty"
        XCTAssertEqual(WindowClassifier.classify(facts), .tiled)
    }

    func testAnITerm2WindowTilesOnlyWithAFullscreenButton() {
        var facts = standard
        facts.bundleId = "com.googlecode.iterm2"
        facts.fullscreenButtonEnabled = false
        XCTAssertEqual(WindowClassifier.classify(facts), .tiled)
        facts.hasFullscreenButton = false
        XCTAssertFalse(WindowClassifier.isWindow(facts))
        XCTAssertEqual(WindowClassifier.classify(facts), .popup)
    }

    func testADialogSubroleWithACloseButtonFloats() {
        var facts = standard
        facts.subrole = "AXDialog"
        XCTAssertTrue(WindowClassifier.isWindow(facts))
        XCTAssertEqual(WindowClassifier.classify(facts), .floating)
    }

    func testAButtonlessUnfocusedUnknownSubroleWindowIsAPopup() {
        let facts = WindowFacts(
            role: "AXWindow",
            subrole: "AXUnknown",
            title: "",
            isFocused: false,
            isMain: false,
            bundleId: "com.example.app"
        )
        XCTAssertFalse(WindowClassifier.isWindow(facts))
        XCTAssertEqual(WindowClassifier.classify(facts), .popup)
        var titled = facts
        titled.title = "Window"
        XCTAssertEqual(WindowClassifier.classify(titled), .popup)
    }

    func testAnUnreadableFocusFieldDoesNotMakeAButtonlessDialogAPopup() {
        var facts = WindowFacts(
            role: "AXWindow",
            subrole: "AXDialog",
            title: "",
            isFocused: false,
            isMain: false,
            bundleId: "com.example.app"
        )
        XCTAssertFalse(WindowClassifier.isWindow(facts))
        facts.isFocused = nil
        XCTAssertTrue(WindowClassifier.isWindow(facts))
        facts.isFocused = false
        facts.isMain = nil
        XCTAssertTrue(WindowClassifier.isWindow(facts))
        XCTAssertEqual(WindowClassifier.classify(facts), .floating)
    }

    func testAnAccessoryAppWindowWithoutACloseButtonIsAPopup() {
        var facts = standard
        facts.hasCloseButton = false
        facts.isAccessoryApp = true
        XCTAssertEqual(WindowClassifier.classify(facts), .popup)
        facts.hasCloseButton = true
        XCTAssertEqual(WindowClassifier.classify(facts), .tiled)
    }

    func testANilRoleIsAPopup() {
        var facts = standard
        facts.role = nil
        XCTAssertEqual(WindowClassifier.classify(facts), .popup)
    }

    func testAFullscreenWindowFloats() {
        var facts = standard
        facts.isFullscreen = true
        XCTAssertEqual(WindowClassifier.classify(facts), .floating)
    }
}
