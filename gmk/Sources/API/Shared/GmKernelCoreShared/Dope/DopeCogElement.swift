import Foundation

/// COGS — Coordination Of General Systems: the mass-relationship layer naming
/// a project's primary systems and how they fit together, where the
/// persistence tree models what the project STORES.
///
/// `dope_cog_element.element_type` carries NO CHECK constraint; validity lives
/// in the registry below and is enforced at read, alongside the structural
/// guarantee that exactly one subtype row exists per element. Adding a type is
/// one case, one registry entry, one subtype table — never a migration.
enum DopeCogElementType: String, Codable, Hashable, CaseIterable, Sendable {
    /// A fundamental organizational boundary of the project — the things a
    /// repo actually splits along (daemon / app / bot, or backend /
    /// frontend). Hulls are top-level and cannot nest.
    case hull = "Hull"
    /// Names a persistence domain that a Hull OWNS. One element per owned
    /// domain: multiplicity is expressed as sibling elements rather than a
    /// many-valued field, which is what keeps the registry's
    /// one-type-one-subtype-table shape intact. Ownership only — a consumer
    /// is not modeled, and must not be synthesized on read.
    case persistenceOwner = "PersistenceOwner"
}

/// Fields a cog element may own beyond the shared ones.
///
/// Mirrors DopeField's role for the persistence levels.
enum DopeCogField: String, Codable, Hashable, CaseIterable, Sendable {
    case primaryPath
    case dopeScopeCode
    /// The owned persistence domain's CODE. A code, never a uuid: ingest
    /// re-mints every child uuid, so a uuid here would go stale on the next
    /// re-ingest.
    case dopePersistenceCode

    /// The subtype table column this field lands in.
    var dbColumn: String {
        switch self {
        case .primaryPath: return "primary_path"
        case .dopeScopeCode: return "dope_scope_code"
        case .dopePersistenceCode: return "dope_persistence_code"
        }
    }
}

/// One element type's registration: its subtype table, the fields it owns, and
/// what may parent it.
///
/// The single truth consumed by the CRUD verbs, the hydration pass, and the
/// validator.
struct DopeCogElementSpec: Sendable {
    let type: DopeCogElementType
    /// Where this type's typed metadata lives — the diagram_drawing_stroke
    /// shape, one table per type.
    let subtypeTable: String
    /// Fields this type MAY carry.
    let ownedFields: Set<DopeCogField>
    /// Fields this type MUST carry.
    ///
    /// Distinct from ownedFields on purpose: the two were conflated while
    /// primary_path happened to be both, and a second type with a different
    /// required field is exactly what breaks that coincidence.
    let requiredFields: Set<DopeCogField>
    /// nil = top level only.
    let allowedParentTypes: Set<DopeCogElementType>?

    static let all: [DopeCogElementType: DopeCogElementSpec] = [
        .hull: DopeCogElementSpec(
            type: .hull,
            subtypeTable: "dope_cog_hull",
            ownedFields: [.primaryPath, .dopeScopeCode],
            requiredFields: [.primaryPath],
            allowedParentTypes: nil
        ),
        .persistenceOwner: DopeCogElementSpec(
            type: .persistenceOwner,
            subtypeTable: "dope_cog_persistence_owner",
            ownedFields: [.dopePersistenceCode],
            requiredFields: [.dopePersistenceCode],
            // Links live on a Hull and nowhere else.
            allowedParentTypes: [.hull]
        ),
    ]

    /// Looks up the specification for a cog element type.
    ///
    /// Throws on an unknown value rather than letting a bad row render
    /// plausibly. This is the constraint the column does not carry.
    /// - Parameter raw: The element type string value.
    /// - Returns: The specification for that type.
    /// - Throws: `StoreError.badRequest` if the type is unknown.
    static func spec(for raw: String) throws -> DopeCogElementSpec {
        guard let type = DopeCogElementType(rawValue: raw), let spec = all[type] else {
            throw StoreError.badRequest(
                detail: "unknown cog element_type '\(raw)' (known: "
                    + DopeCogElementType.allCases.map(\.rawValue).joined(separator: ", ") + ")"
            )
        }
        return spec
    }
}

/// The sub-loadable areas of a dope scope.
///
/// Each carries its own content_revision so a client can ask "did cogs
/// change?" without pulling the persistence tree, and vice versa.
enum DopeArea: String, Codable, Hashable, CaseIterable, Sendable {
    case persistence
    case cogs

    // The DopeArea -> TABLE NAME mapping deliberately does NOT live here. A
    // table name is persistence knowledge, and this is the base layer: the
    // concept belongs here, the storage it happens to sit in does not. See
    // `DopeArea.table` in gmDaemon.
    //
    // The alternative was making that mapping `public` so the repositories
    // could read it across the module boundary, which would have published a
    // schema detail on a domain type to work around a misfiling.
}
