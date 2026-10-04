import Foundation

/// Pure layout: dope tree → one all-or-nothing batch laying the whole domain model
/// out as a canvas, one `dope_scope` container plus one `dope_entity` card per
/// entity in per-domain columns.
///
/// Card geometry comes from the renderer's cardHeight + entityCard, so the
/// generated layout cannot drift from what the screenshot draws. With `replacing`,
/// element_delete mutations for every current top-level element precede the adds,
/// so one batch-apply swaps the canvas atomically.
enum DopeCanvasLayout {

    /// Layout-only knobs the renderer does not own (points, pre-scale).
    struct Metrics {
        var xPitch: Double = 310
        var domainGap: Double = 40
        var yGap: Double = 48
        var maxCardsPerColumn: Int = 5

        /// Creates layout metrics with default values.
        init() {}
    }

    /// Returns diagram mutations to lay out a dope tree as a canvas.
    /// - Parameters:
    ///   - tree: The dope scope tree to lay out.
    ///   - existing: The current diagram elements to replace; defaults to empty.
    ///   - environment: The diagram render environment; defaults to new instance.
    ///   - metrics: The layout metrics; defaults to standard values.
    /// - Returns: An array of diagram mutations to apply atomically.
    static func mutations(
        for tree: DopeScopeTree,
        replacing existing: [DiagramElementNode] = [],
        environment: DiagramRenderEnvironment = .init(),
        metrics: Metrics = .init()
    ) -> [DiagramMutation] {
        var mutations = deletions(of: existing)

        mutations.append(
            .elementAdd(
                DiagramElementAdd(
                    payload: .dopeScopePersistenceLayer(
                        DopeScopePersistenceLayerPayload(dopeScopeCode: tree.body.code)
                    ),
                    clientRef: "scope",
                    code: "scope_\(tree.body.code)",
                    name: tree.body.name,
                    centerX: 0,
                    centerY: 0,
                    elementZ: 0
                )
            )
        )

        var xCursor = 0.0
        var sort = 0
        for domain in tree.domains.sorted(by: { $0.body.sortOrder < $1.body.sortOrder }) {
            let entities = domain.entities.sorted { $0.body.sortOrder < $1.body.sortOrder }
            guard !entities.isEmpty else { continue }
            let columns = Int(ceil(Double(entities.count) / Double(metrics.maxCardsPerColumn)))
            let perColumn = Int(ceil(Double(entities.count) / Double(columns)))
            for column in 0..<columns {
                let columnX = xCursor + Double(column) * metrics.xPitch
                var yCursor = 0.0
                for entity in entities.dropFirst(column * perColumn).prefix(perColumn) {
                    let entityCode = "\(domain.body.code).\(entity.body.code)"
                    let rows = DiagramResolver.entityCard(entityCode, in: tree)?.rows.count ?? 1
                    let height = environment.cardHeight(rowCount: rows)
                    sort += 1
                    mutations.append(
                        .elementAdd(
                            DiagramElementAdd(
                                payload: .dopeEntity(DopeEntityPayload(entityCode: entityCode)),
                                parentClientRef: "scope",
                                code: "\(domain.body.code)_\(entity.body.code)",
                                name: entity.body.name,
                                sortOrder: sort,
                                centerX: columnX,
                                centerY: yCursor + height / 2,
                                elementZ: Double(sort)
                            )
                        )
                    )
                    yCursor += height + metrics.yGap
                }
            }
            xCursor += Double(columns) * metrics.xPitch + metrics.domainGap
        }
        return mutations
    }

    /// Returns one version-pinned element delete per existing element, in input order.
    ///
    /// - Parameter existing: The current diagram elements to remove.
    /// - Returns: The delete mutations for `existing`.
    private static func deletions(of existing: [DiagramElementNode]) -> [DiagramMutation] {
        existing.map { element in
            .elementDelete(
                DiagramElementDelete(
                    elementUuid: element.identity.uuid,
                    expectedVersion: element.identity.version
                )
            )
        }
    }
}
