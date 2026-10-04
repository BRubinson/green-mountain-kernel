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

    /// Counts of rows each `dope_persistence` cascades.
    ///
    /// - Parameter persistenceUuid: The persistence record UUID.
    /// - Returns: A query to fetch the cascade counts.
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

/// One `dope_cog_element` row with whichever subtype row its type owns.
///
/// The two spec-chosen columns ride LEFT JOINs on the element read instead
/// of one statement per element; the mapping consults the spec to ignore a
/// joined row the element type does not own.
struct DopeCogElementWithSubtypes: FetchableRecord, Decodable {
    var element: DopeCogElementRecord
    var hull: DopeCogHullRecord?
    var persistenceOwner: DopeCogPersistenceOwnerRecord?

    /// Widens an element request with the two optional subtype joins.
    ///
    /// Spelled once for the standalone read and for the cog prefetch that
    /// nests it.
    /// - Parameter request: The element request or association to widen.
    /// - Returns: The same request with both subtype rows joined.
    static func joined<R: DerivableRequest>(_ request: R) -> R
    where R.RowDecoder == DopeCogElementRecord {
        request
            .including(optional: DopeCogElementRecord.hull)
            .including(optional: DopeCogElementRecord.persistenceOwner)
    }

    /// Fetches one element with its subtype rows.
    ///
    /// - Returns: A query to fetch elements with their subtype rows.
    static func request() -> QueryInterfaceRequest<Self> {
        joined(DopeCogElementRecord.all()).asRequest(of: Self.self)
    }
}

/// One `dope_cog` row with its elements, in two statements rather than one
/// element query per cog.
///
/// The prefetch is unfiltered: a cog element's `deleted_on` rides out on the
/// wire node, because a whiteout is only meaningful to the masking resolver if
/// it is visible. The subtype columns ride the element prefetch's two joins.
struct DopeCogWithElements: FetchableRecord, Decodable {
    var cog: DopeCogRecord
    var elements: [DopeCogElementWithSubtypes]

    /// Fetches a cog and its elements with their subtype rows.
    ///
    /// - Returns: A query to fetch the cog with its elements.
    static func request() -> QueryInterfaceRequest<Self> {
        DopeCogRecord
            .including(
                all: DopeCogElementWithSubtypes.joined(
                    DopeCogRecord.elements.order(Column("sort_order"), Column("code"))
                )
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

    /// Fetches a property's origin with its entity.
    ///
    /// - Parameter propertyUuid: The property UUID.
    /// - Returns: A query to fetch the property origin data.
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

/// The two codes an entity's or an enum's dot-path is built from.
///
/// The root table differs per builder; the decoded shape does not.
struct DopeDomainChildPath: FetchableRecord, Decodable {
    var domainCode: String
    var childCode: String

    /// Fetches the domain and entity codes for each entity.
    ///
    /// - Returns: A query to fetch entity path codes.
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

    /// Fetches the domain and enum codes for each enum option.
    ///
    /// - Returns: A query to fetch enum path codes.
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

    /// Entities outside a domain that compose a base inside it.
    ///
    /// Identifies entities that would be stranded by a whole-domain delete.
    ///
    /// - Parameter persistenceUuid: The persistence domain UUID.
    /// - Returns: A query to fetch composing entities outside the domain.
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

    /// Fetches the domain, entity, and property codes for each property.
    ///
    /// - Returns: A query to fetch property path codes.
    static func properties() -> QueryInterfaceRequest<Self> {
        propertyBase().asRequest(of: Self.self)
    }

    /// The property projection, typed to the record for further joins.
    ///
    /// Maintains the record type to allow builders below to add joins; a
    /// request typed to the composite accepts only predicates.
    ///
    /// - Returns: A query typed to the property record.
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

    /// Fetches the domain, enum, and option codes for each enum option.
    ///
    /// - Returns: A query to fetch enum option path codes.
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

    /// Properties pointing into an entity from another entity.
    ///
    /// Both referrer columns land on `dope_persistence_entity_property` and
    /// reach the entity the same way, so one builder serves relationship
    /// targets and base origins alike.
    ///
    /// - Parameters:
    ///   - entityUuid: The target entity UUID.
    ///   - association: The association to join through.
    /// - Returns: A query to fetch properties reaching into the entity.
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

    /// Properties outside a domain that point into it.
    ///
    /// Identifies properties that would be stranded by a whole-domain delete.
    ///
    /// - Parameter persistenceUuid: The persistence domain UUID.
    /// - Returns: A query to fetch properties reaching into the domain.
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

    /// Properties outside a domain materialized from a base inside it.
    ///
    /// Kept apart from `propertiesReachingInto` because `base_origin` is
    /// data_type-independent and guarded separately.
    ///
    /// - Parameter persistenceUuid: The persistence domain UUID.
    /// - Returns: A query to fetch materialized properties from the domain.
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

    /// Properties outside a domain, filtered via the entity association.
    ///
    /// The domain is reached through a property's entity, so the predicate
    /// filters on the join, not the root.
    ///
    /// - Parameter persistenceUuid: The persistence domain UUID to filter out.
    /// - Returns: A query to fetch properties outside the domain.
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

    /// Properties inside a domain.
    ///
    /// - Parameter persistenceUuid: The persistence domain UUID to filter by.
    /// - Returns: A query to fetch property UUIDs inside the domain.
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

    /// Fetches materialized properties and their base origins for an entity.
    ///
    /// - Parameter entityUuid: The entity UUID.
    /// - Returns: A query to fetch materialized properties and their origins.
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

    /// Counts the persistence records in a scope.
    ///
    /// - Parameter scopeUuid: The scope UUID.
    /// - Returns: A query to fetch the persistence count.
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
