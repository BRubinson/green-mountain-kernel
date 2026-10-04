// db → wire for the doped records and composites.
//
// This is the only place a doped persistence type and a wire Row meet. Wire
// Rows carry no GRDB conformance and no custom decoder; a record hands one
// over through `dto()` and nothing else.

import Foundation

extension DopeScopeRecord {
    /// Converts the scope record to a wire row.
    ///
    /// Every parameter is passed explicitly, including the three the wire
    /// init defaults (projectUuid, instanceUuid, deletedOn). Omitting
    /// `deletedOn` here would COMPILE and would quietly un-delete every
    /// tombstoned dope node for all 14 readers of this row.
    ///
    /// - Returns: A `DopeScopeRow` representing this scope.
    func dto() -> DopeScopeRow {
        DopeScopeRow(
            uuid: uuid,
            version: version,
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
            updatedAt: updatedAt,
            projectUuid: projectUuid
        )
    }
}

extension DopeNodeRecord {
    /// Extracts the identity fields shared by all dope node types.
    ///
    /// Each of the five dope node tables carries the same BaseEntity columns
    /// plus `deleted_on`. The identity is passed explicitly to avoid quietly
    /// un-deleting tombstoned nodes when the wire init defaults are used.
    ///
    /// - Returns: A `DopeNodeIdentity` with the record's identity fields.
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
    /// Converts the cog record to a wire node with hydrated elements.
    ///
    /// Per-type subtype values are resolved from a runtime-chosen table the
    /// cog spec names.
    ///
    /// - Parameter elements: The hydrated element nodes for this cog.
    /// - Returns: A `DopeCogNode` representing this cog with its elements.
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

extension DopeCogElementWithSubtypes {
    /// Converts the element and its subtype rows to a wire node.
    ///
    /// The spec decides which subtype value the element type owns; a joined
    /// row for a type that does not own it is ignored.
    ///
    /// - Parameter spec: The element type's spec, naming its owned fields.
    /// - Returns: A `DopeCogElementNode` representing this element.
    func dto(spec: DopeCogElementSpec) -> DopeCogElementNode {
        DopeCogElementNode(
            uuid: element.uuid,
            version: element.version,
            elementType: element.elementType,
            code: element.code,
            name: element.name,
            description: element.description,
            sortOrder: Int(element.sortOrder),
            parentElementUuid: element.parentElementUuid,
            dopeScopeCode: element.dopeScopeCode,
            primaryPath: spec.ownedFields.contains(.primaryPath) ? hull?.primaryPath : nil,
            deletedOn: element.deletedOn,
            dopePersistenceCode: spec.ownedFields.contains(.dopePersistenceCode)
                ? persistenceOwner?.dopePersistenceCode : nil
        )
    }
}
