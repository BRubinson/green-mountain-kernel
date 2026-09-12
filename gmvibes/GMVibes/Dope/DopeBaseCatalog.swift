import SwiftUI
import GMCCDaemonKit

/// Cross-domain index over ONE already-loaded `DopeScopeTree`: entity ref
/// (`domain.entity`) → node, base-domain classification, and the inherited
/// property set an entity composes through its `base_composable_ref` chain.
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

    init(tree: DopeScopeTree) {
        for domain in tree.domains {
            for entity in domain.entities {
                let ref = DopeCode.formatEntityRef(
                    domain: domain.body.code, entity: entity.body.code)
                entitiesByRef[ref] = entity
            }
        }
    }

    /// Base domain = holds at least one BASE_COMPOSABLE entity. Mixed domains
    /// count as base (user-confirmed rule).
    static func isBaseDomain(_ domain: DopePersistenceNode) -> Bool {
        domain.entities.contains {
            $0.body.entityType == DopeEntityType.baseComposable.rawValue
        }
    }

    /// The full effective inherited set for `entity`, walking its
    /// `base_composable_ref` chain (daemon-guaranteed acyclic; a visited set
    /// guards against a malformed tree anyway). Union in chain order with the
    /// shadow dedupe: an inherited property is suppressed when a local row
    /// materializes it (`base_origin_ref` equals its full path), when a local
    /// row already carries the same code, or when a nearer chain link already
    /// contributed that code.
    func inheritedProperties(for entity: DopeEntityNode) -> [InheritedProperty] {
        let materializedOrigins = Set(entity.properties.compactMap(\.body.baseOriginRef))
        var seenCodes = Set(entity.properties.map(\.body.code))
        var out: [InheritedProperty] = []
        var nextRef = entity.body.baseComposableRef
        var visited = Set<String>()
        while let ref = nextRef, visited.insert(ref).inserted,
              let base = entitiesByRef[ref], let parsed = try? DopeCode.parseEntityRef(ref, field: "base_composable_ref"),
              case .entity(let domain, let entityCode) = parsed {
            for property in base.properties {
                let fullPath = DopeCode.formatPropertyRef(
                    domain: domain, entity: entityCode, property: property.body.code)
                guard !materializedOrigins.contains(fullPath),
                      seenCodes.insert(property.body.code).inserted else { continue }
                out.append(InheritedProperty(node: property, originRef: fullPath))
            }
            nextRef = base.body.baseComposableRef
        }
        return out
    }
}
