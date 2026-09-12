import Foundation

/// The six DOPED tree levels. `enumeration`'s and `persistence`'s raw-value
/// renames are wire-safe: the CodingKeys hazard documented in Envelope.swift
/// applies to property keys under the snake_case strategies, not to enum raw
/// values.
public enum DopeLevel: String, Codable, Hashable, CaseIterable, Sendable {
    case scope
    /// Renamed from `domain` when the Dope*Domain* vocabulary became
    /// Dope*Persistence* down to the SQL. The ON-DISK .doped.json grammar
    /// deliberately still says "domains" — see DopeMainDocument.
    case persistence
    case entity
    case property
    case enumeration = "enum"
    case option

    /// Accepts the retired "domain" spelling so a stale peer, a scripted
    /// call, or a queued request still resolves. Decoding is tolerant;
    /// encoding always emits the current raw value.
    public init?(fromWire raw: String) {
        if raw == "domain" { self = .persistence; return }
        self.init(rawValue: raw)
    }
}

/// Field identifiers a granular node mutation may carry. Which subset is
/// legal at which level is the registry's `ownedFields` — stated once, so a
/// misdirected field is a precise BAD_REQUEST instead of a silent no-op.
public enum DopeField: String, Codable, Hashable, CaseIterable, Sendable {
    case code, name, description, sortOrder
    case entityType, repoRepresentativeFile, baseComposableUuid
    case dataType, nullable, isUnique, autoIncrement, textCharLimit
    case enumUuid, relationshipTargetUuid, baseOriginPropertyUuid
}

/// One level's registration: table name, parent linkage, legal field set.
/// The registry is the single truth consumed by the generic store mutations,
/// the tree fetch, the projection, and the validator — adding a level later
/// is one entry here plus one CLI verb triple.
public struct DopeLevelSpec: Sendable {
    public let level: DopeLevel
    public let table: String
    public let parentLevel: DopeLevel?
    public let parentColumn: String?
    public let ownedFields: Set<DopeField>

    public static let all: [DopeLevel: DopeLevelSpec] = {
        let common: Set<DopeField> = [.code, .name, .description, .sortOrder]
        let specs: [DopeLevelSpec] = [
            DopeLevelSpec(level: .scope, table: "dope_scope",
                          parentLevel: nil, parentColumn: nil,
                          ownedFields: [.code, .name, .description]),
            DopeLevelSpec(level: .persistence, table: "dope_persistence",
                          parentLevel: .scope, parentColumn: "dope_scope_uuid",
                          ownedFields: common),
            DopeLevelSpec(level: .entity, table: "dope_persistence_entity",
                          parentLevel: .persistence, parentColumn: "dope_persistence_uuid",
                          ownedFields: common.union([.entityType, .repoRepresentativeFile,
                                                     .baseComposableUuid])),
            DopeLevelSpec(level: .property, table: "dope_persistence_entity_property",
                          parentLevel: .entity, parentColumn: "dope_persistence_entity_uuid",
                          ownedFields: common.union([.dataType, .nullable, .isUnique,
                                                     .autoIncrement, .textCharLimit,
                                                     .enumUuid, .relationshipTargetUuid,
                                                     .baseOriginPropertyUuid])),
            DopeLevelSpec(level: .enumeration, table: "dope_persistence_enum",
                          parentLevel: .persistence, parentColumn: "dope_persistence_uuid",
                          ownedFields: common.union([.repoRepresentativeFile])),
            DopeLevelSpec(level: .option, table: "dope_persistence_enum_option",
                          parentLevel: .enumeration, parentColumn: "dope_persistence_enum_uuid",
                          ownedFields: common),
        ]
        return Dictionary(uniqueKeysWithValues: specs.map { ($0.level, $0) })
    }()

    public static func spec(for level: DopeLevel) -> DopeLevelSpec {
        // The registry is total over DopeLevel by construction.
        all[level]!
    }
}

/// DopeScope.scope_type values — the four-tier ladder (m0013).
///
/// The two retired spellings map one-to-one onto the session tiers, which is
/// what made the widening drop-in: SESSION_BASE became SESSION_INSTANCE and
/// PROMPT became SESSION_INSTANCE_ITEM, a pure value rename.
public enum DopeScopeType: String, Codable, Hashable, CaseIterable, Sendable {
    /// Project-wide shared truth, promoted from the primary branch's
    /// SESSION_INSTANCE scope. Always fully hydrated.
    case baseProject = "BASE_PROJECT"
    /// Personal, db-only overlay masking BASE_PROJECT by dot-path position.
    case projectItem = "PROJECT_ITEM"
    /// One session+instance's tree — what .gmcc actually carries, and
    /// what boot sync reconciles against.
    case sessionInstance = "SESSION_INSTANCE"
    /// Personal, db-only overlay masking SESSION_INSTANCE.
    case sessionInstanceItem = "SESSION_INSTANCE_ITEM"

    /// Accepts the retired on-disk/wire spellings. Every committed
    /// main.doped.json says "SESSION_BASE"; the file self-updates on its next
    /// write-repo. Decoding is tolerant, encoding always emits the current
    /// raw value.
    public init?(fromWire raw: String) {
        switch raw {
        case "SESSION_BASE": self = .sessionInstance
        case "PROMPT":       self = .sessionInstanceItem
        default:             self.init(rawValue: raw)
        }
    }

    /// True for the two personal masking tiers. Expressed ONCE so
    /// overlay-vs-base logic is never re-derived from `promptUuid == nil`,
    /// which would compile and be silently wrong for a PROJECT_ITEM.
    public var isOverlay: Bool { self == .projectItem || self == .sessionInstanceItem }

    /// The tier this one masks, or nil for a base tier.
    public var masks: DopeScopeType? {
        switch self {
        case .projectItem: return .baseProject
        case .sessionInstanceItem: return .sessionInstance
        case .baseProject, .sessionInstance: return nil
        }
    }

    /// Session-owned tiers carry session_uuid (and instance_uuid); the
    /// project tiers carry neither.
    public var isSessionOwned: Bool {
        self == .sessionInstance || self == .sessionInstanceItem
    }
}

/// DopePersistenceEntity.entity_type values.
public enum DopeEntityType: String, Codable, Hashable, CaseIterable, Sendable {
    case model = "MODEL"
    case junction = "JUNCTION"
    /// Not persisted on its own — a shared column block other entities
    /// compose in via base_composable_uuid. Only a BASE_COMPOSABLE may be a
    /// base_composable_uuid target.
    case baseComposable = "BASE_COMPOSABLE"
}

/// DopePersistenceEntityProperty.data_type values — the prompt's enum verbatim.
public enum DopePropertyDataType: String, Codable, Hashable, CaseIterable, Sendable {
    case enumeration = "enum"
    case relationship
    case boolean
    case uuid
    case int
    case long
    case decimal
    case text
    case datetime
}
