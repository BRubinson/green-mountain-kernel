import XCTest
@testable import GMCCDaemonKit

/// The generated layout must agree with what the renderer draws: card
/// heights come from the SAME formula (DiagramRenderEnvironment.cardHeight +
/// DiagramResolver.entityCard), columns wrap at maxCardsPerColumn, empty
/// domains are skipped, and regenerate batches delete before adding.
final class DopeCanvasLayoutTests: XCTestCase {

    private func identity(_ uuid: String) -> DopeNodeIdentity {
        DopeNodeIdentity(uuid: uuid, version: 1, createdAt: "t", updatedAt: "t")
    }

    private func property(_ code: String) -> DopePropertyNode {
        DopePropertyNode(
            identity: identity("p-\(code)"),
            body: DopePropertyBody(
                code: code, name: code, description: "", sortOrder: 0,
                dataType: "text", nullable: true, isUnique: false,
                autoIncrement: nil, textCharLimit: nil,
                enumRef: nil, relationshipTargetRef: nil, baseOriginRef: nil))
    }

    private func entity(
        _ code: String, sortOrder: Int = 0, properties: Int,
        entityType: String = "MODEL", base: String? = nil
    ) -> DopeEntityNode {
        DopeEntityNode(
            identity: identity("e-\(code)"),
            body: DopeEntityBody(
                code: code, name: code.capitalized, entityType: entityType,
                description: "", sortOrder: sortOrder,
                repoRepresentativeFile: nil, baseComposableRef: base),
            properties: (0..<properties).map { property("\(code)_p\($0)") })
    }

    private func tree(domains: [DopePersistenceNode]) -> DopeScopeTree {
        DopeScopeTree(
            identity: identity("scope"),
            body: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
            sessionUuid: "s", promptUuid: nil, scopeType: "SESSION_BASE",
            revision: 1, domains: domains)
    }

    private func domain(
        _ code: String, sortOrder: Int = 0, entities: [DopeEntityNode]
    ) -> DopePersistenceNode {
        DopePersistenceNode(
            identity: identity("d-\(code)"),
            body: DopePersistenceBody(code: code, name: code, description: "",
                                 sortOrder: sortOrder),
            entities: entities, enums: [])
    }

    private func adds(_ mutations: [DiagramMutation]) -> [DiagramElementAdd] {
        mutations.compactMap {
            if case .elementAdd(let add) = $0 { return add }
            return nil
        }
    }

    func testCardGeometryMatchesRendererFormula() {
        let t = tree(domains: [
            domain("core", entities: [entity("user", properties: 3)])
        ])
        let environment = DiagramRenderEnvironment()
        let cards = adds(DopeCanvasLayout.mutations(for: t, environment: environment))
            .filter { if case .dopeEntity = $0.payload { return true }; return false }
        XCTAssertEqual(cards.count, 1)
        let rows = DiagramResolver.entityCard("core.user", in: t)!.rows.count
        XCTAssertEqual(rows, 3)
        // centerY = height/2 for the first card in a column.
        XCTAssertEqual(cards[0].centerY, environment.cardHeight(rowCount: rows) / 2)
    }

    func testBaseComposableChainCountsIntoHeight() {
        let t = tree(domains: [
            domain("core", entities: [
                entity("base", properties: 2, entityType: "BASE_COMPOSABLE"),
                entity("user", sortOrder: 1, properties: 3, base: "core.base"),
            ])
        ])
        let rows = DiagramResolver.entityCard("core.user", in: t)!.rows.count
        XCTAssertEqual(rows, 5, "own properties + composed base union")
        let environment = DiagramRenderEnvironment()
        let userCard = adds(DopeCanvasLayout.mutations(for: t, environment: environment))
            .first { $0.code == "core_user" }!
        // Second card in the column: base card's height + gap + half of own.
        let baseHeight = environment.cardHeight(rowCount: 2)
        let expected = baseHeight + DopeCanvasLayout.Metrics().yGap
            + environment.cardHeight(rowCount: 5) / 2
        XCTAssertEqual(userCard.centerY, expected)
    }

    func testColumnsWrapAtMaxCardsPerColumn() {
        let entities = (0..<7).map { entity("e\($0)", sortOrder: $0, properties: 1) }
        let t = tree(domains: [domain("core", entities: entities)])
        let cards = adds(DopeCanvasLayout.mutations(for: t))
            .filter { $0.code != "scope_gmcc" }
        XCTAssertEqual(cards.count, 7)
        let xs = Set(cards.map { $0.centerX ?? -1 })
        XCTAssertEqual(xs.count, 2, "7 entities at max 5/column = 2 columns")
    }

    func testEmptyDomainsAreSkippedAndScopeIsFirstAdd() {
        let t = tree(domains: [
            domain("empty", entities: []),
            domain("core", sortOrder: 1, entities: [entity("user", properties: 1)]),
        ])
        let mutations = DopeCanvasLayout.mutations(for: t)
        let allAdds = adds(mutations)
        XCTAssertEqual(allAdds.count, 2, "scope container + one card; empty domain skipped")
        if case .dopeScopePersistenceLayer(let payload) = allAdds[0].payload {
            XCTAssertEqual(payload.dopeScopeCode, "gmcc")
        } else {
            XCTFail("first add must be the scope container")
        }
    }

    func testRegenerateDeletesPrecedeAdds() {
        let existingElement = DiagramElementNode(
            identity: identity("old-1"),
            base: DiagramElementBase(code: "x", name: "x", description: "",
                                     sortOrder: 0, centerX: 0, centerY: 0,
                                     elementZ: 0, scale: 1),
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: "gmcc")),
            children: [])
        let t = tree(domains: [domain("core", entities: [entity("user", properties: 1)])])
        let mutations = DopeCanvasLayout.mutations(for: t, replacing: [existingElement])
        guard case .elementDelete(let delete) = mutations[0] else {
            return XCTFail("first mutation must delete the old top-level element")
        }
        XCTAssertEqual(delete.elementUuid, "old-1")
        XCTAssertEqual(delete.expectedVersion, 1)
        XCTAssertTrue(mutations.dropFirst().allSatisfy { $0.kind == "element_add" })
    }
}
