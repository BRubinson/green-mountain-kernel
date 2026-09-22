// db → wire for the doped records and composites.
//
// This is the only place a doped persistence type and a wire Row meet. Wire
// Rows carry no GRDB conformance and no custom decoder; a record hands one
// over through `dto()` and nothing else.

import Foundation

extension DopeScopeRecord {
    /// db → wire.
    ///
    /// Every parameter is passed explicitly, including the three the wire
    /// init defaults (projectUuid, instanceUuid, deletedOn). Omitting
    /// `deletedOn` here would COMPILE and would quietly un-delete every
    /// tombstoned dope node for all 14 readers of this row.
    func dto() -> DopeScopeRow {
        DopeScopeRow(
            uuid: uuid,
            version: version,
            projectUuid: projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: sessionUuid,
            promptUuid: promptUuid,
            scopeType: scopeType,
            code: code,
            name: name,
            description: description,
            revision: revision,
            deletedOn: deletedOn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension DopeNodeRecord {
    /// One identity shape over the five dope node tables: each carries the
    /// same BaseEntity columns plus `deleted_on`.
    ///
    /// `deletedOn` is passed explicitly. Omitting it would COMPILE, because
    /// the wire init defaults it, and would quietly un-delete every tombstoned
    /// node the masking resolver relies on seeing.
    func identity() -> DopeNodeIdentity {
        DopeNodeIdentity(
            uuid: uuid,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedOn: deletedOn
        )
    }
}

extension DopeDomainChildPath {
    /// db → the dot-path grammar. `DopeCode` owns the spelling, so a referrer
    /// report and a ref written into the tree cannot drift apart.
    var entityDotPath: String {
        DopeCode.formatEntityRef(domain: domainCode, entity: childCode)
    }

    var enumDotPath: String {
        DopeCode.formatEnumRef(domain: domainCode, enumCode: childCode)
    }
}

extension DopeDomainGrandchildPath {
    var propertyDotPath: String {
        DopeCode.formatPropertyRef(
            domain: domainCode,
            entity: parentCode,
            property: childCode
        )
    }

    var optionDotPath: String {
        DopeCode.formatEnumRef(domain: domainCode, enumCode: parentCode) + ".\(childCode)"
    }
}

extension DopeCogRecord {
    /// db → wire. The elements arrive hydrated: their per-type subtype values
    /// are resolved from a runtime-chosen table the cog spec names.
    func dto(elements: [DopeCogElementNode]) -> DopeCogNode {
        DopeCogNode(
            uuid: uuid,
            version: version,
            code: code,
            name: name,
            description: description,
            sortOrder: Int(sortOrder),
            deletedOn: deletedOn,
            elements: elements
        )
    }
}

extension DopeCogElementRecord {
    /// db → wire. The two subtype values are read separately, because the
    /// column set differs per element type.
    func dto(primaryPath: String?, dopePersistenceCode: String?) -> DopeCogElementNode {
        DopeCogElementNode(
            uuid: uuid,
            version: version,
            elementType: elementType,
            code: code,
            name: name,
            description: description,
            sortOrder: Int(sortOrder),
            parentElementUuid: parentElementUuid,
            dopeScopeCode: dopeScopeCode,
            primaryPath: primaryPath,
            dopePersistenceCode: dopePersistenceCode,
            deletedOn: deletedOn
        )
    }
}
