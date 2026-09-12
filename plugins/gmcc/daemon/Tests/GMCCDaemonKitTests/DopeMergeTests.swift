import XCTest
@testable import GMCCDaemonKit

/// The per-element boundary rule, tested as pure logic: no repo, no daemon,
/// no db. "Files always win for things we didn't edit ourselves, but
/// conflicting data needs resolution."
final class DopeMergeTests: XCTestCase {

    private func el(_ path: String, _ hash: String, kind: String = "entity") -> DopeMerge.Element {
        DopeMerge.Element(dotPath: path, kind: kind, contentHash: hash)
    }
    private func base(_ hash: String?, dirty: Bool) -> DopeMerge.Base {
        DopeMerge.Base(syncedContentHash: hash, locallyModified: dirty)
    }
    private func decision(_ plan: [DopeMerge.Outcome], _ path: String) -> DopeMerge.Decision? {
        plan.first { $0.dotPath == path }?.decision
    }

    /// The headline case: untouched here, changed on disk → the file wins,
    /// with no conflict and nothing to ask about.
    func testUntouchedElementTakesTheFileEvenWhenItChanged() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "OLD")],
            theirs: [el("core.user", "NEW")],
            base: ["core.user": base("OLD", dirty: false)])
        XCTAssertEqual(decision(plan, "core.user"), .takeTheirs)
        XCTAssertTrue(DopeMerge.conflicts(in: plan).isEmpty)
    }

    /// Edited here, untouched on disk → keep ours. Without the base hash
    /// this case is indistinguishable from a conflict.
    func testLocallyEditedAndFileUnchangedKeepsOurs() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "MINE")],
            theirs: [el("core.user", "BASE")],
            base: ["core.user": base("BASE", dirty: true)])
        XCTAssertEqual(decision(plan, "core.user"), .keepOurs)
        XCTAssertTrue(DopeMerge.conflicts(in: plan).isEmpty)
    }

    /// Both moved → a real conflict. This is the only case that needs a
    /// human, and it must not be resolved by guessing.
    func testBothChangedIsAConflict() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "MINE")],
            theirs: [el("core.user", "THEIRS")],
            base: ["core.user": base("BASE", dirty: true)])
        XCTAssertEqual(decision(plan, "core.user"), .conflict)
        XCTAssertEqual(DopeMerge.conflicts(in: plan).map(\.dotPath), ["core.user"])
    }

    /// A dirty element with NO recorded base is a conflict, not a silent
    /// win for either side: without a base there is no evidence about
    /// whether the file moved.
    func testDirtyWithoutABaseIsAConflictRatherThanAGuess() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "MINE")],
            theirs: [el("core.user", "THEIRS")],
            base: ["core.user": base(nil, dirty: true)])
        XCTAssertEqual(decision(plan, "core.user"), .conflict)
    }

    func testLocalAdditionSurvivesAMergeThatNeverSawIt() {
        let plan = DopeMerge.plan(
            ours: [el("core.invented", "MINE")],
            theirs: [],
            base: [:])
        XCTAssertEqual(decision(plan, "core.invented"), .keepOursLocalAddition)
    }

    /// Upstream deleted it and we never touched it → the delete wins.
    func testUpstreamDeleteWinsWhenWeDidNotTouchIt() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "SAME")],
            theirs: [],
            base: ["core.user": base("SAME", dirty: false)])
        XCTAssertEqual(decision(plan, "core.user"), .takeTheirs)
    }

    /// Upstream deleted it but we edited it → a conflict, because silently
    /// discarding a local edit is exactly the failure the rule exists to
    /// prevent.
    func testUpstreamDeleteAgainstALocalEditIsAConflict() {
        let plan = DopeMerge.plan(
            ours: [el("core.user", "MINE")],
            theirs: [],
            base: ["core.user": base("BASE", dirty: true)])
        XCTAssertEqual(decision(plan, "core.user"), .conflict)
    }

    func testNewUpstreamElementIsTaken() {
        let plan = DopeMerge.plan(
            ours: [], theirs: [el("core.fresh", "NEW")], base: [:])
        XCTAssertEqual(decision(plan, "core.fresh"), .takeTheirs)
    }

    /// The plan is total: every path on either side gets an outcome, so a
    /// mixed tree cannot silently drop half of itself.
    func testPlanCoversTheUnionOfBothSides() {
        let plan = DopeMerge.plan(
            ours: [el("a.x", "1"), el("b.y", "2")],
            theirs: [el("b.y", "2"), el("c.z", "3")],
            base: [:])
        XCTAssertEqual(plan.map(\.dotPath), ["a.x", "b.y", "c.z"])
    }

    // MARK: - Element extraction

    /// The hash must be computed over the bytes that would actually be
    /// written, and must be stable — an unstable hash would report phantom
    /// conflicts on every boot.
    func testElementHashingIsStableAndContentSensitive() {
        let a = DopeMerge.hash(DopePersistenceBody(
            code: "core", name: "Core", description: "", sortOrder: 0))
        let b = DopeMerge.hash(DopePersistenceBody(
            code: "core", name: "Core", description: "", sortOrder: 0))
        let c = DopeMerge.hash(DopePersistenceBody(
            code: "core", name: "Core", description: "changed", sortOrder: 0))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    /// Dot-paths must match the addressing dope refs already use, so a
    /// reported conflict names something a person can go and open.
    func testElementsAreAddressedByDotPath() {
        let bundle = DopeDocumentBundle(
            main: DopeScopeDocument(
                version: 1,
                scope: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                persistence: ["core": DopeScopeDocument.expectedFile(forPersistenceCode: "core")]),
            domainFiles: [DopePersistenceFileDocument(
                version: 1,
                body: DopePersistenceBody(code: "core", name: "Core",
                                          description: "", sortOrder: 0),
                entities: [DopeEntityDocument(
                    body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                         description: "", sortOrder: 0,
                                         repoRepresentativeFile: nil, baseComposableRef: nil),
                    properties: [DopePropertyDocument(
                        body: DopePropertyBody(
                            code: "id", name: "Id", description: "", sortOrder: 0,
                            dataType: "uuid", nullable: false, isUnique: true,
                            autoIncrement: nil, textCharLimit: nil, enumRef: nil,
                            relationshipTargetRef: nil, baseOriginRef: nil))])],
                enums: [DopeEnumDocument(
                    body: DopeEnumBody(code: "status", name: "Status", description: "",
                                       sortOrder: 0, repoRepresentativeFile: nil),
                    options: [DopeOptionDocument(
                        body: DopeOptionBody(code: "active", name: "Active",
                                             description: "", sortOrder: 0))])])])

        XCTAssertEqual(DopeMerge.elements(of: bundle).map(\.dotPath), [
            "core",
            "core.user",
            "core.user.id",
            "core.enums.status",
            "core.enums.status.active",
        ])
    }
}
