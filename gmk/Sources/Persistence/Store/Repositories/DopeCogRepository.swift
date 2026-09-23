import Foundation
import GRDB

/// COGS CRUD data access.
///
/// A cog is a named grouping inside a dope scope; its elements are typed nodes
/// whose per-type metadata lives in a subtype table chosen by the
/// DopeCogElementSpec registry. Runs INSIDE a Store-owned transaction; holds no
/// dbQueue and never self-transacts.
struct DopeCogRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    // MARK: - Cog

    /// Adds a new cog to a scope.
    ///
    /// - Parameter req: The cog creation request, including the scope UUID, code, name, and other fields.
    /// - Returns: A response with the created cog and its revision.
    /// - Throws: `StoreError.notFound` if the scope does not exist; `StoreError` errors on code validation or insert failure.
    func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try DopeCode.validateCode(req.code, field: "cog code")
        guard let scope = try dope.fetchDopeScope(uuid: req.scopeUuid) else {
            throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
        }
        let uuid = try core.insertBase(
            db,
            table: "dope_cog",
            extra: [
                "dope_scope_uuid": req.scopeUuid,
                "code": req.code, "name": req.name,
                "description": req.description ?? "",
                "sort_order": req.sortOrder ?? 0,
            ]
        )
        let revision = try dope.bumpScopeRevision(
            scopeUuid: req.scopeUuid,
            area: .cogs,
            ownerUuid: uuid
        )
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_add",
            level: nil,
            nodeUuid: uuid,
            revision: revision
        )
        return try fetchCogResponse(uuid: uuid, revision: revision)
    }

    /// Updates an existing cog.
    ///
    /// - Parameter req: The cog update request with UUID, expected version, and fields to update.
    /// - Returns: A response with the updated cog and its new revision.
    /// - Throws: `StoreError.emptyUpdate` if no fields are provided; `StoreError` errors on code validation or update failure.
    func dopeCogUpdate(_ req: DopeCogUpdateRequest) throws -> DopeCogResponse {
        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let code = req.code {
            try DopeCode.validateCode(code, field: "cog code")
            set["code"] = code
        }
        if let name = req.name { set["name"] = name }
        if let description = req.description { set["description"] = description }
        if let sortOrder = req.sortOrder { set["sort_order"] = sortOrder }
        guard !set.isEmpty else { throw StoreError.emptyUpdate(entity: "dope_cog") }

        let scope = try cogOwningScope(cogUuid: req.uuid)
        try core.updateBase(
            db,
            table: "dope_cog",
            uuid: req.uuid,
            expectedVersion: req.expectedVersion,
            set: set
        )
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .cogs,
            ownerUuid: req.uuid
        )
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_update",
            level: nil,
            nodeUuid: req.uuid,
            revision: revision
        )
        return try fetchCogResponse(uuid: req.uuid, revision: revision)
    }

    /// Deletes a cog from a scope.
    ///
    /// Soft deletes are only allowed in overlay scopes; hard deletes remove the cog and its elements from the database.
    ///
    /// - Parameter req: The cog deletion request with UUID, expected version, and soft-delete flag.
    /// - Returns: A response with the deleted cog UUID, number of cascaded elements, scope UUID, and revision.
    /// - Throws: `StoreError.badRequest` if soft delete is attempted on a non-overlay scope; `StoreError` errors on delete failure.
    func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        let scope = try cogOwningScope(cogUuid: req.uuid)
        let elements =
            try DopeCogElementRecord
            .filter(DopeCogElementRecord.Columns.dopeCogUuid == req.uuid)
            .fetchCount(db)

        if req.soft == true {
            guard scope.tier?.isOverlay == true else {
                throw StoreError.badRequest(
                    detail: "--soft is only valid inside a masking scope; scope "
                        + "\(scope.uuid) is \(scope.scopeType)"
                )
            }
            try core.updateBase(
                db,
                table: "dope_cog",
                uuid: req.uuid,
                expectedVersion: req.expectedVersion,
                set: ["deleted_on": Store.isoNow()]
            )
        } else {
            try core.deleteBase(
                db,
                table: "dope_cog",
                uuid: req.uuid,
                expectedVersion: req.expectedVersion
            )
        }
        let revision = try dope.bumpScopeRevision(scopeUuid: scope.uuid)
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_delete",
            level: nil,
            nodeUuid: req.uuid,
            revision: revision
        )
        return DopeCogDeleteResponse(
            deletedUuid: req.uuid,
            cascadedElements: elements,
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    // MARK: - Elements

    /// Adds a new element to a cog.
    ///
    /// Validates element type and parent relationship; subtype fields are stored in the
    /// spec's subtype table.
    ///
    /// - Parameter req: The element creation request with cog UUID, element type, code, name, and spec-driven fields.
    /// - Returns: A response with the created element and its revision.
    /// - Throws: `StoreError.notFound` if the cog does not exist; `StoreError.badRequest` for invalid parent relationships; `StoreError` errors on validation or insert failure.
    func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try DopeCode.validateCode(req.code, field: "cog element code")
        let spec = try DopeCogElementSpec.spec(for: req.elementType)
        guard try DopeCogRecord.all().withUuid(req.cogUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: "dope_cog", key: req.cogUuid)
        }
        let scope = try cogOwningScope(cogUuid: req.cogUuid)

        // allowedParentTypes is a two-way constraint: nil means top-level
        // ONLY, and non-nil means parented ONLY. The second half was
        // unreachable while every type was top-level, so a type that
        // must be parented could still be created at the root.
        switch (req.parentElementUuid, spec.allowedParentTypes) {
        case (nil, .some(let allowed)):
            throw StoreError.badRequest(
                detail: "element type '\(spec.type.rawValue)' must be parented under "
                    + allowed.map(\.rawValue).sorted().joined(separator: " or ")
                    + " and cannot be top-level"
            )
        case (.some(let parent), _):
            guard let parentType = try elementType(uuid: parent) else {
                throw StoreError.notFound(entity: "dope_cog_element", key: parent)
            }
            guard let allowed = spec.allowedParentTypes,
                allowed.contains(where: { $0.rawValue == parentType })
            else {
                throw StoreError.badRequest(
                    detail: "element type '\(spec.type.rawValue)' is top-level only "
                        + "and cannot be parented under '\(parentType)'"
                )
            }
        case (nil, nil):
            break  // top-level type at top level
        }

        // Spec-driven rather than a literal special case: PersistenceOwner has
        // no primary_path at all, so a per-type requiredFields loop is what
        // lets a second element type exist.
        var subtypeValues: [String: (any DatabaseValueConvertible)?] = [:]
        for field in spec.requiredFields.sorted(by: { $0.rawValue < $1.rawValue }) {
            let supplied: String?
            switch field {
            case .primaryPath: supplied = req.primaryPath
            case .dopePersistenceCode: supplied = req.dopePersistenceCode
            case .dopeScopeCode: supplied = req.dopeScopeCode
            }
            guard let value = supplied, !value.isEmpty else {
                throw StoreError.badRequest(
                    detail: "element type '\(spec.type.rawValue)' requires --"
                        + field.rawValue
                        .replacingOccurrences(
                            of: "([a-z0-9])([A-Z])",
                            with: "$1-$2",
                            options: .regularExpression
                        )
                        .lowercased()
                )
            }
            subtypeValues[field.dbColumn] = value
        }

        let uuid = try core.insertBase(
            db,
            table: "dope_cog_element",
            extra: [
                "dope_cog_uuid": req.cogUuid,
                "parent_element_uuid": req.parentElementUuid,
                "element_type": spec.type.rawValue,
                "code": req.code, "name": req.name,
                "description": req.description ?? "",
                "sort_order": req.sortOrder ?? 0,
                "dope_scope_code": req.dopeScopeCode,
            ]
        )
        subtypeValues["element_uuid"] = uuid
        _ = try core.insertBase(db, table: spec.subtypeTable, extra: subtypeValues)
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .cogs,
            ownerUuid: req.cogUuid
        )
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_element_add",
            level: nil,
            nodeUuid: uuid,
            revision: revision
        )
        return try fetchCogElementResponse(uuid: uuid, revision: revision)
    }

    /// Updates an existing cog element.
    ///
    /// - Parameter req: The element update request with UUID, expected version, and fields to update.
    /// - Returns: A response with the updated element and its new revision.
    /// - Throws: `StoreError.notFound` if the element does not exist; `StoreError.badRequest` for invalid field updates; `StoreError` errors on update failure.
    func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        guard let typeRaw = try elementType(uuid: req.uuid) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: req.uuid)
        }
        let spec = try DopeCogElementSpec.spec(for: typeRaw)
        let scope = try elementOwningScope(elementUuid: req.uuid)

        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let code = req.code {
            try DopeCode.validateCode(code, field: "cog element code")
            set["code"] = code
        }
        if let name = req.name { set["name"] = name }
        if let description = req.description { set["description"] = description }
        if let sortOrder = req.sortOrder { set["sort_order"] = sortOrder }
        if req.clearDopeScopeCode == true {
            set["dope_scope_code"] = nil
        } else if let binding = req.dopeScopeCode {
            set["dope_scope_code"] = binding
        }

        if let primaryPath = req.primaryPath {
            guard spec.ownedFields.contains(.primaryPath) else {
                throw StoreError.badRequest(
                    detail: "element type '\(typeRaw)' does not own --primary-path"
                )
            }
            try db.execute(
                sql: """
                    UPDATE \(spec.subtypeTable) SET primary_path = ?, updated_at = ?
                     WHERE element_uuid = ?
                    """,
                arguments: [primaryPath, Store.isoNow(), req.uuid]
            )
        } else if set.isEmpty {
            throw StoreError.emptyUpdate(entity: "dope_cog_element")
        }

        if !set.isEmpty {
            try core.updateBase(
                db,
                table: "dope_cog_element",
                uuid: req.uuid,
                expectedVersion: req.expectedVersion,
                set: set
            )
        }
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .cogs,
            ownerUuid: try owningCogUuid(elementUuid: req.uuid)
        )
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_element_update",
            level: nil,
            nodeUuid: req.uuid,
            revision: revision
        )
        return try fetchCogElementResponse(uuid: req.uuid, revision: revision)
    }

    /// Deletes an element from a cog.
    ///
    /// Soft deletes are allowed only in overlay scopes; hard deletes remove the element
    /// and its children from the database.
    ///
    /// - Parameter req: The element deletion request with UUID, expected version, and soft-delete flag.
    /// - Returns: A response with the deleted element UUID, number of cascaded children, scope UUID, and revision.
    /// - Throws: `StoreError.badRequest` if soft delete is attempted on a non-overlay scope; `StoreError` errors on delete failure.
    func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        let scope = try elementOwningScope(elementUuid: req.uuid)
        // Captured BEFORE the delete — a hard delete removes the row this
        // lookup reads, and the area counter still has to be advanced.
        let cogUuid = try owningCogUuid(elementUuid: req.uuid)
        let children =
            try DopeCogElementRecord
            .filter(DopeCogElementRecord.Columns.parentElementUuid == req.uuid)
            .fetchCount(db)
        if req.soft == true {
            guard scope.tier?.isOverlay == true else {
                throw StoreError.badRequest(
                    detail: "--soft is only valid inside a masking scope; scope "
                        + "\(scope.uuid) is \(scope.scopeType)"
                )
            }
            try core.updateBase(
                db,
                table: "dope_cog_element",
                uuid: req.uuid,
                expectedVersion: req.expectedVersion,
                set: ["deleted_on": Store.isoNow()]
            )
        } else {
            try core.deleteBase(
                db,
                table: "dope_cog_element",
                uuid: req.uuid,
                expectedVersion: req.expectedVersion
            )
        }
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .cogs,
            ownerUuid: cogUuid
        )
        try dope.recordDopeChange(
            scope: scope,
            action: "cog_element_delete",
            level: nil,
            nodeUuid: req.uuid,
            revision: revision
        )
        return DopeCogDeleteResponse(
            deletedUuid: req.uuid,
            cascadedElements: children,
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    // MARK: - Read

    /// Fetches cogs from a scope, optionally filtered by code.
    ///
    /// - Parameter req: The fetch request with scope UUID and optional code filter.
    /// - Returns: A response with the matching cogs.
    /// - Throws: `StoreError.notFound` if the scope does not exist; `StoreError` errors on fetch failure.
    func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        guard try dope.fetchDopeScope(uuid: req.scopeUuid) != nil else {
            throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
        }
        var request = Self.cogsOfScope(req.scopeUuid)
        if let code = req.code {
            request = request.filter(DopeCogRecord.Columns.code == code)
        }
        return DopeCogGetResponse(
            cogs: try request.fetchAll(db).map { try hydrateCog($0) }
        )
    }

    /// Fetches every cog of a scope, hydrated for the write path.
    ///
    /// For callers already inside a transaction; the repo write path needs cogs
    /// alongside the persistence tree. Extracted from dopeCogGet to avoid duplication.
    ///
    /// - Parameter scopeUuid: The scope UUID to fetch cogs from.
    /// - Returns: An array of hydrated cogs with their elements.
    /// - Throws: `StoreError` errors on fetch failure.
    func fetchDopeCogs(scopeUuid: String) throws -> [DopeCogNode] {
        try Self.cogsOfScope(scopeUuid).fetchAll(db).map { try hydrateCog($0) }
    }

    /// Fetches a scope's cogs with elements prefetched in a single request.
    ///
    /// Uses two statements for the whole area, never an element query per cog;
    /// the subtype columns ride the element prefetch's joins.
    ///
    /// - Parameter scopeUuid: The scope UUID to fetch cogs from.
    /// - Returns: A request that fetches cogs with their elements prefetched.
    private static func cogsOfScope(
        _ scopeUuid: String
    ) -> QueryInterfaceRequest<DopeCogWithElements> {
        DopeCogWithElements.request()
            .filter(DopeCogRecord.Columns.dopeScopeUuid == scopeUuid)
            .order(DopeCogRecord.Columns.sortOrder, DopeCogRecord.Columns.code)
    }

    // MARK: - Helpers

    /// Returns the element type of a cog element.
    ///
    /// - Parameter uuid: The element UUID.
    /// - Returns: The element type string, or nil if the element does not exist.
    /// - Throws: `StoreError` errors on fetch failure.
    private func elementType(uuid: String) throws -> String? {
        try DopeCogElementRecord
            .all()
            .withUuid(uuid)
            .select(DopeCogElementRecord.Columns.elementType, as: String.self)
            .fetchOne(db)
    }

    /// Fetches the scope containing a cog.
    ///
    /// - Parameter cogUuid: The cog UUID.
    /// - Returns: The scope row containing the cog.
    /// - Throws: `StoreError.notFound` if the cog does not exist; `StoreError` errors on fetch failure.
    private func cogOwningScope(cogUuid: String) throws -> DopeScopeRow {
        guard
            let row =
                try DopeScopeRecord
                .joining(required: DopeScopeRecord.cogs.unordered().withUuid(cogUuid))
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "dope_cog", key: cogUuid)
        }
        return row.dto()
    }

    /// Returns the UUID of the cog containing a cog element.
    ///
    /// - Parameter elementUuid: The element UUID.
    /// - Returns: The UUID of the owning cog.
    /// - Throws: `StoreError.notFound` if the element does not exist; `StoreError` errors on fetch failure.
    private func owningCogUuid(elementUuid: String) throws -> String {
        guard
            let uuid =
                try DopeCogElementRecord
                .all()
                .withUuid(elementUuid)
                .select(DopeCogElementRecord.Columns.dopeCogUuid, as: String.self)
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return uuid
    }

    /// Fetches the scope containing a cog element.
    ///
    /// - Parameter elementUuid: The element UUID.
    /// - Returns: The scope row containing the element's cog.
    /// - Throws: `StoreError.notFound` if the element does not exist; `StoreError` errors on fetch failure.
    private func elementOwningScope(elementUuid: String) throws -> DopeScopeRow {
        guard
            let row =
                try DopeScopeRecord
                .joining(
                    required: DopeScopeRecord.cogs.unordered()
                        .joining(
                            required: DopeCogRecord.elements.unordered().withUuid(elementUuid)
                        )
                )
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return row.dto()
    }

    /// Converts a database cog composite to a cog node, hydrating its elements.
    ///
    /// - Parameter composite: The cog composite with elements prefetched.
    /// - Returns: A hydrated cog node with converted elements.
    /// - Throws: `StoreError` errors on element hydration failure.
    private func hydrateCog(_ composite: DopeCogWithElements) throws -> DopeCogNode {
        composite.cog.dto(
            elements: try composite.elements.map { try hydrateElement($0) }
        )
    }

    /// Converts a cog element with its subtype rows to a node.
    ///
    /// Both subtype rows ride the element read as LEFT JOINs; the spec names
    /// which one the element type owns, and the other is ignored.
    ///
    /// - Parameter element: The cog element with its subtype rows.
    /// - Returns: A hydrated cog element node with type-specific fields.
    /// - Throws: `StoreError` when the element type has no spec.
    private func hydrateElement(_ element: DopeCogElementWithSubtypes) throws -> DopeCogElementNode {
        element.dto(spec: try DopeCogElementSpec.spec(for: element.element.elementType))
    }

    /// Fetches a cog and builds a response with its revision.
    ///
    /// - Parameters:
    ///   - uuid: The cog UUID.
    ///   - revision: The revision number to include in the response.
    /// - Returns: A response with the fetched cog and provided revision.
    /// - Throws: `StoreError.notFound` if the cog does not exist; `StoreError` errors on fetch failure.
    private func fetchCogResponse(
        uuid: String,
        revision: Int64
    ) throws -> DopeCogResponse {
        guard
            let composite = try DopeCogWithElements.request().withUuid(uuid).fetchOne(db)
        else {
            throw StoreError.notFound(entity: "dope_cog", key: uuid)
        }
        return DopeCogResponse(cog: try hydrateCog(composite), revision: revision)
    }

    /// Fetches a cog element and builds a response with its revision.
    ///
    /// - Parameters:
    ///   - uuid: The element UUID.
    ///   - revision: The revision number to include in the response.
    /// - Returns: A response with the fetched element and provided revision.
    /// - Throws: `StoreError.notFound` if the element does not exist; `StoreError` errors on fetch failure.
    private func fetchCogElementResponse(
        uuid: String,
        revision: Int64
    ) throws -> DopeCogElementResponse {
        guard let element = try DopeCogElementWithSubtypes.request().withUuid(uuid).fetchOne(db) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: uuid)
        }
        return DopeCogElementResponse(
            element: try hydrateElement(element),
            revision: revision
        )
    }
}
