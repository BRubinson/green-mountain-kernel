import Foundation

/// COGS — Coordination Of General Systems.
///
/// Where the persistence tree models what the project STORES, a cog tree
/// models how its larger systems fit together: the mass-relationship layer
/// that names a project's primary systems and, later, the wiring between
/// them.
///
/// The registry below is the whole extensibility story, and it exists
/// because of a specific piece of debt. m0010's `diagram_element.element_type`
/// carries a `CHECK (element_type IN (...))`, so adding a type there means
/// rebuilding the table — the same pain m0008 already paid once for
/// dope_domain_entity. `dope_cog_element.element_type` therefore carries NO
/// CHECK. Validity lives here in Swift, enforced at read the way
/// Store+Diagram.fetchElementInfo already does, plus the structural
/// guarantee that exactly one subtype row exists per element.
///
/// Adding a second element type is: one case, one registry entry, one
/// subtype table. Never a migration against dope_cog_element.
public enum DopeCogElementType: String, Codable, Hashable, CaseIterable, Sendable {
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

/// Fields a cog element may own beyond the shared ones. Mirrors DopeField's
/// role for the persistence levels.
public enum DopeCogField: String, Codable, Hashable, CaseIterable, Sendable {
    case primaryPath
    case dopeScopeCode
    /// The owned persistence domain's CODE. A code, never a uuid: ingest
    /// re-mints every child uuid, so a uuid here would go stale on the next
    /// re-ingest.
    case dopePersistenceCode

    /// The subtype table column this field lands in.
    public var dbColumn: String {
        switch self {
        case .primaryPath:         return "primary_path"
        case .dopeScopeCode:       return "dope_scope_code"
        case .dopePersistenceCode: return "dope_persistence_code"
        }
    }
}

/// One element type's registration: its subtype table, the fields it owns,
/// and what may parent it. The single truth consumed by the CRUD verbs, the
/// hydration pass, and the validator.
public struct DopeCogElementSpec: Sendable {
    public let type: DopeCogElementType
    /// Where this type's typed metadata lives — the diagram_drawing_stroke
    /// shape, one table per type.
    public let subtypeTable: String
    /// Fields this type MAY carry.
    public let ownedFields: Set<DopeCogField>
    /// Fields this type MUST carry. Distinct from ownedFields on purpose:
    /// the two were conflated while primary_path happened to be both, and a
    /// second type with a different required field is exactly what breaks
    /// that coincidence.
    public let requiredFields: Set<DopeCogField>
    /// nil = top level only.
    public let allowedParentTypes: Set<DopeCogElementType>?

    public static let all: [DopeCogElementType: DopeCogElementSpec] = [
        .hull: DopeCogElementSpec(
            type: .hull,
            subtypeTable: "dope_cog_hull",
            ownedFields: [.primaryPath, .dopeScopeCode],
            requiredFields: [.primaryPath],
            allowedParentTypes: nil),
        .persistenceOwner: DopeCogElementSpec(
            type: .persistenceOwner,
            subtypeTable: "dope_cog_persistence_owner",
            ownedFields: [.dopePersistenceCode],
            requiredFields: [.dopePersistenceCode],
            // Links live on a Hull and nowhere else.
            allowedParentTypes: [.hull]),
    ]

    /// Throws on an unknown value rather than letting a bad row render as
    /// something plausible. This IS the constraint the column does not carry.
    public static func spec(for raw: String) throws -> DopeCogElementSpec {
        guard let type = DopeCogElementType(rawValue: raw), let spec = all[type] else {
            throw StoreError.badRequest(
                detail: "unknown cog element_type '\(raw)' (known: "
                      + DopeCogElementType.allCases.map(\.rawValue).joined(separator: ", ") + ")")
        }
        return spec
    }
}

/// The sub-loadable areas of a dope scope. Each carries its own
/// content_revision so a client can ask "did cogs change?" without pulling
/// the persistence tree, and vice versa.
public enum DopeArea: String, Codable, Hashable, CaseIterable, Sendable {
    case persistence
    case cogs

    /// The table whose rows carry this area's content_revision.
    var table: String {
        switch self {
        case .persistence: return "dope_persistence"
        case .cogs: return "dope_cog"
        }
    }
}
