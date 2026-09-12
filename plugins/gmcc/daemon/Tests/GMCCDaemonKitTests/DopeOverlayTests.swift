import XCTest
@testable import GMCCDaemonKit

/// The masking resolver. Every test here runs with NO database and NO
/// filesystem — that is the whole argument for the resolver being a pure
/// function over two hydrated trees.
final class DopeOverlayTests: XCTestCase {

    // MARK: - Builders

    private func ident(_ uuid: String, deleted: String? = nil) -> DopeNodeIdentity {
        DopeNodeIdentity(uuid: uuid, version: 0, createdAt: "t", updatedAt: "t",
                         deletedOn: deleted)
    }

    private func prop(_ code: String, uuid: String, desc: String = "",
                      deleted: String? = nil) -> DopePropertyNode {
        DopePropertyNode(
            identity: ident(uuid, deleted: deleted),
            body: DopePropertyBody(code: code, name: code, description: desc, sortOrder: 0,
                                   dataType: "text", nullable: true, isUnique: false,
                                   autoIncrement: nil, textCharLimit: nil, enumRef: nil,
                                   relationshipTargetRef: nil, baseOriginRef: nil))
    }

    private func entity(_ code: String, uuid: String, desc: String = "",
                        deleted: String? = nil,
                        props: [DopePropertyNode] = []) -> DopeEntityNode {
        DopeEntityNode(
            identity: ident(uuid, deleted: deleted),
            body: DopeEntityBody(code: code, name: code, entityType: "MODEL", description: desc,
                                 sortOrder: 0, repoRepresentativeFile: nil,
                                 baseComposableRef: nil),
            properties: props)
    }

    private func domain(_ code: String, uuid: String, desc: String = "",
                        deleted: String? = nil,
                        entities: [DopeEntityNode] = [],
                        enums: [DopeEnumNode] = []) -> DopePersistenceNode {
        DopePersistenceNode(
            identity: ident(uuid, deleted: deleted),
            body: DopePersistenceBody(code: code, name: code, description: desc, sortOrder: 0),
            entities: entities, enums: enums)
    }

    private func tree(_ domains: [DopePersistenceNode], scope: String = "sc") -> DopeScopeTree {
        DopeScopeTree(identity: ident(scope),
                      body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                      sessionUuid: "s", promptUuid: nil,
                      scopeType: DopeScopeType.sessionInstance.rawValue,
                      revision: 1, domains: domains)
    }

    // MARK: - Degenerate layers

    func testNilOverlayResolvesToTheBaseUnchanged() {
        let base = tree([domain("core", uuid: "d1", entities: [entity("user", uuid: "e1")])])
        let r = DopeOverlay.resolve(base: base, overlay: nil)
        XCTAssertEqual(r.tree.domains.count, 1)
        XCTAssertEqual(r.resolutions["core"]?.origin, .base)
        XCTAssertEqual(r.resolutions["core.user"]?.origin, .base)
        XCTAssertTrue(r.hidden.isEmpty)
    }

    func testMissingBaseIsLegalAndWarned() {
        let overlay = tree([domain("core", uuid: "o1")])
        let r = DopeOverlay.resolve(base: nil, overlay: overlay)
        XCTAssertEqual(r.tree.domains.count, 1)
        XCTAssertFalse(r.warnings.isEmpty, "a base-less overlay must warn, not throw")
    }

    // MARK: - Override

    func testOverlayBodyWinsWholesaleAndProvenanceNamesBothRows() {
        let base = tree([domain("core", uuid: "d1", desc: "base text")])
        let overlay = tree([domain("core", uuid: "o1", desc: "my text")])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains[0].body.description, "my text")
        let res = r.resolutions["core"]
        XCTAssertEqual(res?.origin, .overridden)
        XCTAssertEqual(res?.baseUuid, "d1")
        XCTAssertEqual(res?.overlayUuid, "o1")
        XCTAssertEqual(res?.effectiveUuid, "o1",
                       "effectiveUuid must name the row a write would hit")
    }

    /// Copy-on-write: an untouched sibling still points at the BASE row, so a
    /// caller that writes it knows it is writing the shared layer.
    func testUntouchedSiblingKeepsTheBaseRowAsEffective() {
        let base = tree([domain("core", uuid: "d1", entities: [
            entity("user", uuid: "e1"), entity("team", uuid: "e2"),
        ])])
        let overlay = tree([domain("core", uuid: "o1", entities: [
            entity("user", uuid: "oe1", desc: "mine"),
        ])])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.resolutions["core.user"]?.effectiveUuid, "oe1")
        XCTAssertEqual(r.resolutions["core.team"]?.effectiveUuid, "e2")
        XCTAssertEqual(r.resolutions["core.team"]?.origin, .base)
    }

    // MARK: - PASSTHROUGH

    /// Copy-up is what makes "present in the overlay overrides" exact. An
    /// ancestor carried along for a deeper edit holds the BASE's real values,
    /// so overriding wholesale reproduces them rather than blanking them.
    /// This is the property that replaced the PASSTHROUGH marker.
    func testCopiedAncestorsCarryTheBaseValuesForward() {
        let base = tree([domain("core", uuid: "d1", desc: "REAL DOMAIN TEXT", entities: [
            entity("user", uuid: "e1", desc: "REAL ENTITY TEXT",
                   props: [prop("id", uuid: "p1", desc: "REAL PROP TEXT")]),
        ])])
        // Copy-up: the ancestors are faithful copies of the base, and only
        // the leaf carries the user's edit.
        let overlay = tree([domain("core", uuid: "o1", desc: "REAL DOMAIN TEXT", entities: [
            entity("user", uuid: "oe1", desc: "REAL ENTITY TEXT",
                   props: [prop("id", uuid: "op1", desc: "MY PROP TEXT")]),
        ])])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains[0].body.description, "REAL DOMAIN TEXT",
                       "a copied ancestor lost the base's text")
        XCTAssertEqual(r.tree.domains[0].entities[0].body.description, "REAL ENTITY TEXT",
                       "a copied ancestor lost the base's text")
        XCTAssertEqual(r.tree.domains[0].entities[0].properties[0].body.description,
                       "MY PROP TEXT", "the real overlay leaf must win")
        // Every copied node reads as an override now — there is no marker
        // and no special case, which is the whole simplification.
        XCTAssertEqual(r.resolutions["core"]?.origin, .overridden)
        XCTAssertEqual(r.resolutions["core.user.id"]?.origin, .overridden)
    }

    // MARK: - Whiteout

    func testTombstoneHidesTheBaseNodeAndItsSubtree() {
        let base = tree([domain("core", uuid: "d1", entities: [
            entity("user", uuid: "e1", props: [prop("id", uuid: "p1")]),
            entity("team", uuid: "e2"),
        ])])
        let overlay = tree([domain("core", uuid: "o1", entities: [
            entity("user", uuid: "oe1", deleted: "2026-09-07T00:00:00Z"),
        ])])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains[0].entities.map { $0.body.code }, ["team"],
                       "the whiteout must remove the node from the resolved tree")
        XCTAssertTrue(r.hidden.contains("core.user"))
        XCTAssertEqual(r.resolutions["core.user"]?.origin, .tombstoned)
    }

    func testTombstonedPropertyIsHiddenButSiblingsSurvive() {
        let base = tree([domain("core", uuid: "d1", entities: [
            entity("user", uuid: "e1", props: [prop("id", uuid: "p1"), prop("name", uuid: "p2")]),
        ])])
        let overlay = tree([domain("core", uuid: "o1", entities: [
            entity("user", uuid: "oe1",
                   props: [prop("id", uuid: "op1", deleted: "2026-09-07T00:00:00Z")]),
        ])])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains[0].entities[0].properties.map { $0.body.code }, ["name"])
        XCTAssertTrue(r.hidden.contains("core.user.id"))
    }

    // MARK: - Add

    func testOverlayOnlyNodesAreAdditions() {
        let base = tree([domain("core", uuid: "d1", entities: [entity("user", uuid: "e1")])])
        let overlay = tree([domain("core", uuid: "o1", entities: [
            entity("scratch", uuid: "oe9"),
        ])])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains[0].entities.map { $0.body.code }, ["user", "scratch"])
        XCTAssertEqual(r.resolutions["core.scratch"]?.origin, .added)
        XCTAssertNil(r.resolutions["core.scratch"]?.baseUuid)
    }

    // MARK: - Orphaned mask

    /// A base is free to evolve out from under a personal overlay. That is a
    /// warning and never blocks the base — the same posture as a dangling
    /// diagram binding.
    func testWhiteoutOverAVanishedBaseNodeIsAnOrphanedMaskNotAnError() {
        let base = tree([domain("core", uuid: "d1")])
        let overlay = tree([domain("gone", uuid: "o9", deleted: "2026-09-07T00:00:00Z")])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.resolutions["gone"]?.origin, .orphanedMask)
        XCTAssertTrue(r.hidden.contains("gone"))
        XCTAssertTrue(r.warnings.contains { $0.contains("orphaned mask") })
        XCTAssertEqual(r.tree.domains.map { $0.body.code }, ["core"])
    }

    // MARK: - Structural invariants

    func testBaseOrderingIsPreserved() {
        let base = tree([domain("a", uuid: "d1"), domain("b", uuid: "d2"),
                         domain("c", uuid: "d3")])
        let overlay = tree([domain("b", uuid: "o2", desc: "mine")])
        let r = DopeOverlay.resolve(base: base, overlay: overlay)
        XCTAssertEqual(r.tree.domains.map { $0.body.code }, ["a", "b", "c"],
                       "a merge must not reshuffle the shared tree")
    }

    func testFlattenedYieldsAPlainTreeForDownstreamConsumers() {
        let base = tree([domain("core", uuid: "d1")])
        let flat: DopeScopeTree = DopeOverlay.resolve(base: base, overlay: nil).flattened()
        XCTAssertEqual(flat.body.code, "gmcc")
        XCTAssertEqual(flat.revision, 1)
    }

    /// gm doctor calls this best-effort; a throwing merge would break its
    /// exit contract. There is deliberately no throwing path to test — this
    /// asserts the degenerate shapes all return.
    func testResolveNeverThrowsOnDegenerateInput() {
        _ = DopeOverlay.resolve(base: nil, overlay: nil)
        _ = DopeOverlay.resolve(base: tree([]), overlay: tree([]))
        _ = DopeOverlay.resolve(
            base: tree([domain("x", uuid: "d", deleted: "t")]),
            overlay: tree([domain("x", uuid: "o", deleted: "t")]))
    }
}
