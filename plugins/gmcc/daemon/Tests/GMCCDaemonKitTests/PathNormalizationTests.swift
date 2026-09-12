import XCTest
@testable import GMCCDaemonKit

/// The comparison feature's join-key contract. Purely lexical — the live db
/// includes an instance root with a space that no longer exists on disk
/// ("/Users/brycerubinson/My project"), so the normalizer must never touch
/// the filesystem.
final class PathNormalizationTests: XCTestCase {
    private let root = "/Users/dev/repo"

    private func normalize(_ raw: String, root: String? = nil) throws -> String {
        try Store.normalizeRepoRelativePath(raw, repoRoot: root ?? self.root)
    }

    func testRelativePassesThroughCleaned() throws {
        XCTAssertEqual(try normalize("Sources/App.swift"), "Sources/App.swift")
        XCTAssertEqual(try normalize("./Sources/App.swift"), "Sources/App.swift")
        XCTAssertEqual(try normalize("Sources//App.swift"), "Sources/App.swift")
        XCTAssertEqual(try normalize("  Sources/App.swift \n"), "Sources/App.swift")
        // Bare basenames are legal — root-level files are real, and planned
        // files usually don't exist yet.
        XCTAssertEqual(try normalize("Package.swift"), "Package.swift")
    }

    func testAbsoluteInsideInstanceStripped() throws {
        XCTAssertEqual(try normalize("/Users/dev/repo/Sources/App.swift"), "Sources/App.swift")
        XCTAssertEqual(try normalize("/Users/dev/repo/Sources/App.swift", root: "/Users/dev/repo/"),
                       "Sources/App.swift")
    }

    func testAbsoluteOutsideInstanceRejected() throws {
        XCTAssertThrowsError(try normalize("/etc/passwd"))
        // Component-boundary check: /Users/dev/repo2 is NOT inside /Users/dev/repo.
        XCTAssertThrowsError(try normalize("/Users/dev/repo2/App.swift"))
    }

    func testPathologicalInstanceRoot() throws {
        // Space in the root, path does not exist on disk — must still work.
        XCTAssertEqual(
            try normalize("/Users/brycerubinson/My project/App.swift",
                          root: "/Users/brycerubinson/My project"),
            "App.swift")
    }

    func testEscapesAndDegeneratesRejected() throws {
        XCTAssertThrowsError(try normalize(""))
        XCTAssertThrowsError(try normalize("   "))
        XCTAssertThrowsError(try normalize("../outside.swift"))
        XCTAssertThrowsError(try normalize("Sources/../../outside.swift"))
        XCTAssertThrowsError(try normalize("/Users/dev/repo"))
        XCTAssertThrowsError(try normalize("bad\npath"))
    }
}
