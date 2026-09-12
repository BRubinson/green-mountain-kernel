import Foundation

/// Pure layout: dope tree → one all-or-nothing batch that lays the whole
/// domain model out as a canvas — one `dope_scope` container plus one
/// `dope_entity` card per entity, grouped in per-domain columns. Replaces
/// scripts/diagram_from_dope.py: card geometry comes from
/// `DiagramRenderEnvironment.cardHeight` + `DiagramResolver.entityCard` (the
/// renderer's own row resolution, base-composable chain included), so the
/// generated layout can NEVER drift from what the screenshot draws.
///
/// With `replacing`, the batch is a full regenerate: element_delete
/// mutations for every current top-level element (subtree CASCADE) precede
/// the adds, so one batch-apply swaps the canvas atomically under the
/// diagram-revision CAS. Empty domains are skipped.
public enum DopeCanvasLayout {

    /// Layout-only knobs the renderer does not own (points, pre-scale).
    public struct Metrics {
        public var xPitch: Double = 310
        public var domainGap: Double = 40
        public var yGap: Double = 48
        public var maxCardsPerColumn: Int = 5
        public init() {}
    }

    public static func mutations(
        for tree: DopeScopeTree,
        replacing existing: [DiagramElementNode] = [],
        environment: DiagramRenderEnvironment = .init(),
        metrics: Metrics = .init()
    ) -> [DiagramMutation] {
        var mutations: [DiagramMutation] = []

        for element in existing {
            mutations.append(.elementDelete(DiagramElementDelete(
                elementUuid: element.identity.uuid,
                expectedVersion: element.identity.version)))
        }

        mutations.append(.elementAdd(DiagramElementAdd(
            clientRef: "scope",
            code: "scope_\(tree.body.code)",
            name: tree.body.name,
            centerX: 0, centerY: 0, elementZ: 0,
            payload: .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: tree.body.code)))))

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
                    mutations.append(.elementAdd(DiagramElementAdd(
                        parentClientRef: "scope",
                        code: "\(domain.body.code)_\(entity.body.code)",
                        name: entity.body.name,
                        sortOrder: sort,
                        centerX: columnX,
                        centerY: yCursor + height / 2,
                        elementZ: Double(sort),
                        payload: .dopeEntity(DopeEntityPayload(entityCode: entityCode)))))
                    yCursor += height + metrics.yGap
                }
            }
            xCursor += Double(columns) * metrics.xPitch + metrics.domainGap
        }
        return mutations
    }
}
