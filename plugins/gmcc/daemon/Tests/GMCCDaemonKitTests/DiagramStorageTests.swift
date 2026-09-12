import XCTest
@testable import GMCCDaemonKit

/// CKFS-rooted render paths and the staleness key.
///
/// The path arithmetic is pure, so it is tested without a filesystem. The
/// fingerprint is tested for the property that actually matters: that it
/// notices the inputs a naive timestamp check cannot see.
final class DiagramStorageTests: XCTestCase {

    // MARK: - Path derivation, all three tiers

    /// The whole point of moving to CKFS: every tier has a storage root, so
    /// PROJECT stops being the special case that could not render at all.
    func testEveryTierDerivesAScreenshotPath() throws {
        let project = try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo",
            gmccDiagramPath: nil, diagramCode: "domain")
        XCTAssertEqual(project, "projects/repo/diagrams/screenshots/domain.png")

        let session = try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo/instances/repo_1/sessions/main",
            gmccDiagramPath: nil, diagramCode: "domain")
        XCTAssertEqual(
            session,
            "projects/repo/instances/repo_1/sessions/main/diagrams/screenshots/domain.png")

        let prompt = try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo/instances/repo_1/sessions/main/prompts/9_x",
            gmccDiagramPath: nil, diagramCode: "domain")
        XCTAssertTrue(prompt.hasSuffix("prompts/9_x/diagrams/screenshots/domain.png"))
    }

    /// gmcc_diagram_path stops being inert free-text: it is the directory
    /// override, and it may be nested.
    func testGmccDiagramPathOverridesTheDefaultDirectory() throws {
        XCTAssertEqual(
            try DiagramStorage.screenshotRelativePath(
                ownerStoragePath: "projects/repo", gmccDiagramPath: "docs/architecture",
                diagramCode: "domain"),
            "projects/repo/docs/architecture/screenshots/domain.png")
    }

    func testFingerprintSidecarSitsBesideItsPng() throws {
        let png = try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo", gmccDiagramPath: nil, diagramCode: "d")
        let sidecar = try DiagramStorage.fingerprintRelativePath(
            ownerStoragePath: "projects/repo", gmccDiagramPath: nil, diagramCode: "d")
        XCTAssertEqual(png.replacingOccurrences(of: ".png", with: ".render.json"), sidecar)
    }

    // MARK: - Containment (defence in depth, before the sandbox even runs)

    func testTraversalAndAbsolutePathsAreRefused() {
        // A stored path climbing out of the CKFS root.
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/../../etc", gmccDiagramPath: nil, diagramCode: "d"))
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo", gmccDiagramPath: "../../etc",
            diagramCode: "d"))
        // Absolute owner paths are a category error: these are CKFS-relative.
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "/etc", gmccDiagramPath: nil, diagramCode: "d"))
        // A code carrying a separator would smuggle a directory.
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo", gmccDiagramPath: nil,
            diagramCode: "../escape"))
        // Dotfiles are refused so a render can never shadow a config file.
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "projects/repo", gmccDiagramPath: ".git",
            diagramCode: "d"))
        // Empty is not a root.
        XCTAssertThrowsError(try DiagramStorage.screenshotRelativePath(
            ownerStoragePath: "", gmccDiagramPath: nil, diagramCode: "d"))
    }

    // MARK: - The staleness key

    /// THE reason the fingerprint exists.
    ///
    /// An entity card's rows come from the bound dope tree. Editing a dope
    /// property changes the rendered picture while `diagram.revision` and
    /// its `updated_at` sit perfectly still — so a revision check, or an
    /// mtime check, reports "fresh" and hands a bot a stale image under a
    /// current-looking path. The dope revisions are in the key precisely so
    /// that cannot happen.
    func testDopeRevisionChangeInvalidatesTheRenderEvenWhenTheDiagramIsUntouched() {
        let before = DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665], scheme: "light", scale: 2)
        let after = DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,          // unchanged
            dopeRevisions: ["gmcc": 700], scheme: "light", scale: 2)
        XCTAssertFalse(before.matches(after),
                       "a dope edit MUST invalidate the render — this is the bug the "
                     + "fingerprint exists to prevent")
    }

    func testEveryInputIsPartOfTheKey() {
        let base = DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665], scheme: "light", scale: 2)
        XCTAssertTrue(base.matches(base))

        XCTAssertFalse(base.matches(DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 8,
            dopeRevisions: ["gmcc": 665], scheme: "light", scale: 2)))
        XCTAssertFalse(base.matches(DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665], scheme: "dark", scale: 2)))
        XCTAssertFalse(base.matches(DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665], scheme: "light", scale: 3)))
        // The render CODE is an input too: change a card metric or the
        // router's padding and every persisted input is identical while the
        // picture is not.
        XCTAssertFalse(base.matches(DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665], scheme: "light", scale: 2,
            algoVersion: DiagramRenderFingerprint.renderAlgoVersion + 1)))
    }

    /// A diagram renamed onto a code another diagram used to own would
    /// otherwise silently inherit that diagram's PNG, since the path is
    /// keyed by code.
    func testDiagramIdentityIsPartOfTheKeySoARenamedCodeCannotInheritAnImage() {
        let mine = DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 1,
            dopeRevisions: [:], scheme: "light", scale: 2)
        let theirs = DiagramRenderFingerprint(
            diagramUuid: "d-2", diagramRevision: 1,
            dopeRevisions: [:], scheme: "light", scale: 2)
        XCTAssertFalse(mine.matches(theirs))
    }

    func testFingerprintRoundTripsThroughItsSidecarEncoding() throws {
        let fingerprint = DiagramRenderFingerprint(
            diagramUuid: "d-1", diagramRevision: 7,
            dopeRevisions: ["gmcc": 665, "other": 12], scheme: "dark", scale: 2)
        let decoded = try XCTUnwrap(
            DiagramRenderFingerprint.decoded(fingerprint.encoded()))
        XCTAssertTrue(fingerprint.matches(decoded))
    }

    func testSidecarEncodingIsStable() throws {
        // Sorted keys: the sidecar is compared by VALUE after decoding, but a
        // stable encoding keeps it diffable and prevents pointless rewrites.
        let a = DiagramRenderFingerprint(
            diagramUuid: "d", diagramRevision: 1,
            dopeRevisions: ["b": 2, "a": 1], scheme: "light", scale: 2)
        let b = DiagramRenderFingerprint(
            diagramUuid: "d", diagramRevision: 1,
            dopeRevisions: ["a": 1, "b": 2], scheme: "light", scale: 2)
        XCTAssertEqual(try a.encoded(), try b.encoded())
    }
}
