// Composite read shapes over the doped tables.
//
// A composite is FetchableRecord + Decodable whose properties are Records,
// arrays of Records, or annotated scalars, and it owns the request that fills
// it. Wire mapping lives in Mapping/, never here.

import Foundation
import GRDB

/// The rows one `dope_persistence` cascades, counted in a single statement.
///
/// Every count is unfiltered. A hard delete takes tombstoned rows with it, so
/// a `notDeleted()` hop on any of these four would under-report the cascade
/// the caller is about to perform.
struct DopePersistenceCascadeCounts: FetchableRecord, Decodable {
    var entityCount: Int
    var enumCount: Int
    var propertyCount: Int
    var optionCount: Int

    static func request(persistenceUuid: String) -> QueryInterfaceRequest<Self> {
        DopePersistenceRecord
            .all()
            .withUuid(persistenceUuid)
            .annotated(
                with: DopePersistenceRecord.entities.unordered().count.forKey("entityCount"),
                DopePersistenceRecord.enums.unordered().count.forKey("enumCount"),
                DopePersistenceRecord.allProperties.unordered().count.forKey("propertyCount"),
                DopePersistenceRecord.allOptions.unordered().count.forKey("optionCount")
            )
            .asRequest(of: Self.self)
    }
}

/// One `dope_cog` row with its elements, in two statements rather than one
/// element query per cog.
///
/// The prefetch is unfiltered: a cog element's `deleted_on` rides out on the
/// wire node, because a whiteout is only meaningful to the masking resolver if
/// it is visible.
struct DopeCogWithElements: FetchableRecord, Decodable {
    var cog: DopeCogRecord
    var elements: [DopeCogElementRecord]

    static func request() -> QueryInterfaceRequest<Self> {
        DopeCogRecord
            .including(
                all: DopeCogRecord.elements
                    .order(Column("sort_order"), Column("code"))
            )
            .asRequest(of: Self.self)
    }
}

/// The chain-non-null tier ladder a session-tier dope scope fills on insert:
/// every ancestor uuid, so a later list or get by any ancestor stays an
/// indexed WHERE.
struct DopeScopeLineage: FetchableRecord, Decodable {
    var projectUuid: String
    var instanceUuid: String

    static func forSession(_ uuid: String) -> QueryInterfaceRequest<Self> {
        let instance = TableAlias<InstanceRecord>()
        return
            SessionRecord
            .all()
            .withUuid(uuid)
            .joining(required: SessionRecord.instance.aliased(instance))
            .select(
                instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid"),
                SessionRecord.Columns.instanceUuid.forKey("instanceUuid")
            )
            .asRequest(of: Self.self)
    }
}

/// A base-origin property's shape plus the entity it sits on, for the
/// materialization guard: the data_type must match and the owning entity must
/// be a BASE_COMPOSABLE the referrer's chain reaches.
struct DopePropertyOrigin: FetchableRecord, Decodable {
    var dataType: String
    var entityUuid: String
    var entityType: String

    static func request(propertyUuid: String) -> QueryInterfaceRequest<Self> {
        let property = TableAlias<DopePersistenceEntityPropertyRecord>()
        let entity = TableAlias<DopePersistenceEntityRecord>()
        return
            DopePersistenceEntityPropertyRecord
            .aliased(property)
            .withUuid(propertyUuid)
            .joining(required: DopePersistenceEntityPropertyRecord.entity.aliased(entity))
            .select(
                property[DopePersistenceEntityPropertyRecord.Columns.dataType].forKey("dataType"),
                entity[DopePersistenceEntityRecord.Columns.uuid].forKey("entityUuid"),
                entity[DopePersistenceEntityRecord.Columns.entityType].forKey("entityType")
            )
            .asRequest(of: Self.self)
    }
}

/// The two codes an entity's or an enum's dot-path is built from. The root
/// table differs per builder; the decoded shape does not.
struct DopeDomainChildPath: FetchableRecord, Decodable {
    var domainCode: String
    var childCode: String

    static func entities() -> QueryInterfaceRequest<Self> {
        let domain = TableAlias<DopePersistenceRecord>()
        return
            DopePersistenceEntityRecord
            .joining(required: DopePersistenceEntityRecord.dopePersistence.aliased(domain))
            .select(
                domain[DopePersistenceRecord.Columns.code].forKey("domainCode"),
                DopePersistenceEntityRecord.Columns.code.forKey("childCode")
            )
            .asRequest(of: Self.self)
    }

    static func enums() -> QueryInterfaceRequest<Self> {
        let domain = TableAlias<DopePersistenceRecord>()
        return
            DopePersistenceEnumRecord
            .joining(required: DopePersistenceEnumRecord.dopePersistence.aliased(domain))
            .select(
                domain[DopePersistenceRecord.Columns.code].forKey("domainCode"),
                DopePersistenceEnumRecord.Columns.code.forKey("childCode")
            )
            .asRequest(of: Self.self)
    }

    /// Entities OUTSIDE one domain that compose a base INSIDE it — what a
    /// whole-domain delete would strand.
    static func entitiesComposingInside(
        persistenceUuid: String
    ) -> QueryInterfaceRequest<Self> {
        entities()
            .filter(DopePersistenceEntityRecord.Columns.dopePersistenceUuid != persistenceUuid)
            .filter(
                DopePersistenceEntityRecord
                    .select(DopePersistenceEntityRecord.Columns.uuid)
                    .filter(
                        DopePersistenceEntityRecord.Columns.dopePersistenceUuid == persistenceUuid
                    )
                    .contains(DopePersistenceEntityRecord.Columns.baseComposableUuid)
            )
    }
}

/// The three codes a property's or an enum option's dot-path is built from.
struct DopeDomainGrandchildPath: FetchableRecord, Decodable {
    var domainCode: String
    var parentCode: String
    var childCode: String

    static func properties() -> QueryInterfaceRequest<Self> {
        propertyBase().asRequest(of: Self.self)
    }

    /// The property projection, still typed to the record so the builders
    /// below can add joins: a request typed to the composite takes only
    /// predicates.
    private static func propertyBase()
        -> QueryInterfaceRequest<DopePersistenceEntityPropertyRecord>
    {
        let domain = TableAlias<DopePersistenceRecord>()
        let entity = TableAlias<DopePersistenceEntityRecord>()
        return
            DopePersistenceEntityPropertyRecord
            .joining(
                required: DopePersistenceEntityPropertyRecord.entity.aliased(entity)
                    .joining(required: DopePersistenceEntityRecord.dopePersistence.aliased(domain))
            )
            .select(
                domain[DopePersistenceRecord.Columns.code].forKey("domainCode"),
                entity[DopePersistenceEntityRecord.Columns.code].forKey("parentCode"),
                DopePersistenceEntityPropertyRecord.Columns.code.forKey("childCode")
            )
    }

    static func options() -> QueryInterfaceRequest<Self> {
        let domain = TableAlias<DopePersistenceRecord>()
        let dopeEnum = TableAlias<DopePersistenceEnumRecord>()
        return
            DopePersistenceEnumOptionRecord
            .joining(
                required: DopePersistenceEnumOptionRecord.dopeEnum.aliased(dopeEnum)
                    .joining(required: DopePersistenceEnumRecord.dopePersistence.aliased(domain))
            )
            .select(
                domain[DopePersistenceRecord.Columns.code].forKey("domainCode"),
                dopeEnum[DopePersistenceEnumRecord.Columns.code].forKey("parentCode"),
                DopePersistenceEnumOptionRecord.Columns.code.forKey("childCode")
            )
            .asRequest(of: Self.self)
    }

    /// Properties pointing into one entity through `column`, from some other
    /// entity. Both referrer columns land on `dope_persistence_entity_property`
    /// and reach the entity the same way, so one builder serves relationship
    /// targets and base origins alike.
    static func propertiesReaching(
        entityUuid: String,
        through association: BelongsToAssociation<
            DopePersistenceEntityPropertyRecord, DopePersistenceEntityPropertyRecord
        >
    ) -> QueryInterfaceRequest<Self> {
        let target = TableAlias<DopePersistenceEntityPropertyRecord>()
        return
            propertyBase()
            .joining(required: association.aliased(target))
            .filter(
                target[DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEntityUuid]
                    == entityUuid
            )
            .filter(
                DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEntityUuid != entityUuid
            )
            .asRequest(of: Self.self)
    }

    /// Properties OUTSIDE one domain that point at an enum or a property
    /// INSIDE it — what a whole-domain delete would strand.
    static func propertiesReachingInto(
        persistenceUuid: String
    ) -> QueryInterfaceRequest<Self> {
        let enumsInside =
            DopePersistenceEnumRecord
            .select(DopePersistenceEnumRecord.Columns.uuid)
            .filter(DopePersistenceEnumRecord.Columns.dopePersistenceUuid == persistenceUuid)
        return
            propertiesOutside(persistenceUuid)
            .filter(
                enumsInside.contains(
                    DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEnumUuid
                )
                    || propertiesInside(persistenceUuid)
                        .contains(
                            DopePersistenceEntityPropertyRecord.Columns.relationshipTargetUuid
                        )
            )
    }

    /// Properties OUTSIDE one domain materialized from a base property INSIDE
    /// it. Kept apart from `propertiesReachingInto` because `base_origin` is
    /// data_type-independent and so is guarded on its own.
    static func propertiesOriginatingInside(
        persistenceUuid: String
    ) -> QueryInterfaceRequest<Self> {
        propertiesOutside(persistenceUuid)
            .filter(
                propertiesInside(persistenceUuid)
                    .contains(
                        DopePersistenceEntityPropertyRecord.Columns.baseOriginPropertyUuid
                    )
            )
    }

    /// The domain a property sits in is reached through its entity, so
    /// "outside this domain" is a predicate on the join, never on the root.
    private static func propertiesOutside(
        _ persistenceUuid: String
    ) -> QueryInterfaceRequest<Self> {
        propertyBase()
            .joining(
                required: DopePersistenceEntityPropertyRecord.entity
                    .filter(
                        DopePersistenceEntityRecord.Columns.dopePersistenceUuid != persistenceUuid
                    )
            )
            .asRequest(of: Self.self)
    }

    private static func propertiesInside(
        _ persistenceUuid: String
    ) -> QueryInterfaceRequest<DopePersistenceEntityPropertyRecord> {
        DopePersistenceEntityPropertyRecord
            .select(DopePersistenceEntityPropertyRecord.Columns.uuid)
            .joining(
                required: DopePersistenceEntityPropertyRecord.entity
                    .filter(
                        DopePersistenceEntityRecord.Columns.dopePersistenceUuid == persistenceUuid
                    )
            )
    }
}

/// One entity's materialized properties with the base entity each originates
/// from — the strand guard's input.
struct DopeMaterializedOrigin: FetchableRecord, Decodable {
    var code: String
    var originEntityUuid: String

    static func request(entityUuid: String) -> QueryInterfaceRequest<Self> {
        let property = TableAlias<DopePersistenceEntityPropertyRecord>()
        let originEntity = TableAlias<DopePersistenceEntityRecord>()
        return
            DopePersistenceEntityPropertyRecord
            .aliased(property)
            .filter(
                DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEntityUuid == entityUuid
            )
            .filter(DopePersistenceEntityPropertyRecord.Columns.baseOriginPropertyUuid != nil)
            .joining(
                required: DopePersistenceEntityPropertyRecord.baseOriginProperty
                    .joining(
                        required: DopePersistenceEntityPropertyRecord.entity.aliased(originEntity)
                    )
            )
            .select(
                property[DopePersistenceEntityPropertyRecord.Columns.code].forKey("code"),
                originEntity[DopePersistenceEntityRecord.Columns.uuid].forKey("originEntityUuid")
            )
            .asRequest(of: Self.self)
    }
}

/// How much persistence tree one scope carries — the promotion guard's probe
/// against blanking a populated base with a virgin source.
///
/// The count is unfiltered, matching the SQL it replaces: a tombstoned node is
/// still content the promotion would carry across.
struct DopeScopePersistenceCount: FetchableRecord, Decodable {
    var persistenceCount: Int

    static func request(scopeUuid: String) -> QueryInterfaceRequest<Self> {
        DopeScopeRecord
            .all()
            .withUuid(scopeUuid)
            .annotated(
                with: DopeScopeRecord.persistences
                    .unordered()
                    .count
                    .forKey("persistenceCount")
            )
            .asRequest(of: Self.self)
    }
}
