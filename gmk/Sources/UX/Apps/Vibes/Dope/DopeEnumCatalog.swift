import SwiftUI

/// Cross-domain index over ONE already-loaded `DopeScopeTree`: enum ref →
/// definition, and enum ref → every property (in ANY domain) pointing at it.
///
/// A pure client-side derivation — DOPE_GET already ships the whole tree, so
/// this costs no daemon call, no wire field, and no cache entry. Rebuilt per
/// `DopeTreeView` body pass rather than cached: the tree is a few hundred nodes
/// and a stale index on a live DOPE_CHANGE reload would be a correctness bug,
/// not a performance win.
struct DopeEnumCatalog: Equatable {

    /// One property that references an enum, plus the domain/entity it lives
    /// on — the row shape the inspector's "Used By" section renders.
    struct Usage: Hashable, Identifiable {
        let propertyUuid: String
        let domainCode: String
        let domainName: String
        let entityCode: String
        let entityName: String
        let propertyCode: String
        let propertyName: String
        let nullable: Bool

        /// `domain.entity.property` — the same greppable dot-path the daemon
        /// writes into `.doped.json` (kit formatter, never string-built here).
        var ref: String {
            DopeCode.formatPropertyRef(
                domain: domainCode,
                entity: entityCode,
                property: propertyCode
            )
        }
        var id: String { propertyUuid }
    }

    /// An enum ref resolved to everything the inspector dialog needs.
    struct Resolved: Identifiable, Hashable {
        let ref: String
        let domainName: String
        let node: DopeEnumNode
        let usages: [Usage]
        var id: String { ref }
    }

    private struct Definition: Hashable {
        let domainName: String
        let node: DopeEnumNode
    }

    private var definitions: [String: Definition] = [:]
    private var usages: [String: [Usage]] = [:]

    /// The empty catalog — the default for previews and the not-yet-loaded case.
    init() {}

    /// Builds a catalog from a dope scope tree.
    /// - Parameter tree: The dope scope tree to index.
    init(tree: DopeScopeTree) {
        for domain in tree.domains {
            for enumNode in domain.enums {
                let ref = DopeCode.formatEnumRef(
                    domain: domain.body.code,
                    enumCode: enumNode.body.code
                )
                definitions[ref] = Definition(domainName: domain.body.name, node: enumNode)
            }
            for entity in domain.entities {
                for property in entity.properties {
                    guard let ref = property.body.enumRef else { continue }
                    usages[ref, default: []]
                        .append(
                            Usage(
                                propertyUuid: property.identity.uuid,
                                domainCode: domain.body.code,
                                domainName: domain.body.name,
                                entityCode: entity.body.code,
                                entityName: entity.body.name,
                                propertyCode: property.body.code,
                                propertyName: property.body.name,
                                nullable: property.body.nullable
                            )
                        )
                }
            }
        }
    }

    /// Looks up an enum definition by reference.
    ///
    /// Returns nil for dangling refs, keeping the row's plain-text render for badge display.
    /// - Parameter ref: The enum reference.
    /// - Returns: The enum node, or nil if not defined.
    func node(for ref: String) -> DopeEnumNode? { definitions[ref]?.node }

    /// Resolves an enum ref to its definition, domain, and all usages.
    /// - Parameter ref: The enum reference.
    /// - Returns: The resolved enum data, or nil if not defined.
    func resolved(_ ref: String) -> Resolved? {
        guard let definition = definitions[ref] else { return nil }
        return Resolved(
            ref: ref,
            domainName: definition.domainName,
            node: definition.node,
            usages: usages[ref] ?? []
        )
    }
}

/// The read-down catalog and the write-up "open the inspector" callback,
/// bundled so `DomainCard` / `EntityRow` each gain exactly ONE parameter —
/// the same explicit threading the file already uses for `query` and
/// `expansion`.
struct DopeEnumInspector {
    var catalog = DopeEnumCatalog()
    /// (enumRef, originating property uuid) — the origin lets the dialog mark
    /// the row the user came from without threading domain/entity codes into
    /// `PropertyRow`, which does not know them.
    var inspect: (String, String?) -> Void = { _, _ in }
}
