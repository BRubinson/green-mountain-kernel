import SwiftUI

/// Cross-domain index over ONE already-loaded `DopeScopeTree`: entity ref
/// (`domain.entity`) → node, base-domain classification, and the inherited
/// property set an entity composes through its `base_composable_ref` chain.
///
/// A pure client-side derivation, rebuilt per `DopeTreeView` body pass for the
/// same staleness reason as `DopeEnumCatalog`.
struct DopeBaseCatalog: Equatable {

    /// One inherited (non-materialized) base property, ready to render as a
    /// dimmed/synthetic row. `node` is the base entity's REAL wire row, so its
    /// uuid is a stable ForEach identity within any one entity's list.
    struct InheritedProperty: Hashable, Identifiable {
        let node: DopePropertyNode
        /// `domain.entity.property` — where the field is declared.
        let originRef: String
        var id: String { node.identity.uuid }
    }

    private var entitiesByRef: [String: DopeEntityNode] = [:]

    /// The empty catalog — the default for previews and the not-yet-loaded case.
    init() {}

    /// Initializes the catalog from a scope tree.
    ///
    /// - Parameter tree: The scope tree to index.
    init(tree: DopeScopeTree) {
        for domain in tree.domains {
            for entity in domain.entities {
                let ref = DopeCode.formatEntityRef(
                    domain: domain.body.code,
                    entity: entity.body.code
                )
                entitiesByRef[ref] = entity
            }
        }
    }

    /// Base domain = holds at least one BASE_COMPOSABLE entity.
    ///
    /// Mixed domains count as base (user-confirmed rule).
    ///
    /// - Parameter domain: The domain to check.
    /// - Returns: `true` if the domain contains a base-composable entity.
    static func isBaseDomain(_ domain: DopePersistenceNode) -> Bool {
        domain.entities.contains {
            $0.body.entityType == DopeEntityType.baseComposable.rawValue
        }
    }

    /// Returns the full effective inherited property set for an entity.
    ///
    /// Walks the entity's `base_composable_ref` chain. The daemon guarantees
    /// acyclicity; a visited set guards against malformed trees. Properties are
    /// deduped: inherited properties are suppressed when a local row materializes
    /// it (matching `base_origin_ref`), or when a local row or nearer chain link
    /// already contributed that code.
    ///
    /// - Parameter entity: The entity to collect inherited properties for.
    /// - Returns: Array of inherited properties, deduplicated and in chain order.
    func inheritedProperties(for entity: DopeEntityNode) -> [InheritedProperty] {
        let materializedOrigins = Set(entity.properties.compactMap(\.body.baseOriginRef))
        var seenCodes = Set(entity.properties.map(\.body.code))
        var out: [InheritedProperty] = []
        var nextRef = entity.body.baseComposableRef
        var visited = Set<String>()
        while let ref = nextRef, visited.insert(ref).inserted,
            let base = entitiesByRef[ref], let parsed = try? DopeCode.parseEntityRef(ref, field: "base_composable_ref"),
            case .entity(let domain, let entityCode) = parsed
        {
            for property in base.properties {
                let fullPath = DopeCode.formatPropertyRef(
                    domain: domain,
                    entity: entityCode,
                    property: property.body.code
                )
                guard !materializedOrigins.contains(fullPath),
                    seenCodes.insert(property.body.code).inserted
                else { continue }
                out.append(InheritedProperty(node: property, originRef: fullPath))
            }
            nextRef = base.body.baseComposableRef
        }
        return out
    }
}
