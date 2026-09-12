import Foundation

/// Cog rows ↔ cog documents. The mirror of DopeProjection for the cogs area.
public enum DopeCogProjection {

    /// db → file. Top-level elements become documents; their PersistenceOwner
    /// children collapse into the parent's `links.persistence_owners`.
    /// Tombstoned rows are dropped, matching the persistence projection.
    public static func document(from cog: DopeCogNode) -> DopeCogDocument {
        let live = cog.elements.filter { $0.deletedOn == nil }
        let byParent = Dictionary(grouping: live.filter { $0.parentElementUuid != nil }) {
            $0.parentElementUuid!
        }
        let roots = live.filter { $0.parentElementUuid == nil }
            .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }

        return DopeCogDocument(
            body: DopeCogBody(code: cog.code, name: cog.name,
                              description: cog.description, sortOrder: cog.sortOrder),
            elements: roots.map { root in
                let owners = (byParent[root.uuid] ?? [])
                    .filter { $0.elementType == DopeCogElementType.persistenceOwner.rawValue }
                    .compactMap(\.dopePersistenceCode)
                    .sorted()
                return DopeCogElementDocument(
                    code: root.code, name: root.name, description: root.description,
                    sortOrder: root.sortOrder, elementType: root.elementType,
                    primaryPath: root.primaryPath, dopeScopeCode: root.dopeScopeCode,
                    links: owners.isEmpty ? nil : DopeCogLinks(persistenceOwners: owners))
            })
    }

    /// One synthesized PersistenceOwner child, as both the reader and the
    /// seeder must mint it. Centralised so the two cannot drift — drift here
    /// would make every publish/ingest cycle produce a different tree and
    /// report phantom conflicts forever.
    public static func ownerElement(
        parentCode: String, persistenceCode: String, sortOrder: Int
    ) -> (code: String, name: String, description: String, sortOrder: Int) {
        (code: "\(parentCode)_owns_\(persistenceCode)",
         name: persistenceCode,
         description: "",
         sortOrder: sortOrder)
    }
}
