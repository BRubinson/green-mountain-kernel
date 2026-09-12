import Foundation
import GRDB

/// COGS CRUD data access. A cog is a named grouping inside a dope scope; its
/// elements are typed nodes whose per-type metadata lives in a subtype table
/// chosen by the DopeCogElementSpec registry. Runs INSIDE a Store-owned
/// transaction; holds no dbQueue and never self-transacts.
struct DopeCogRepository: RepositoryContext {
    let db: Database
    let core: StoreCore


    // MARK: - Cog

    func dopeCogAdd(_ req: DopeCogAddRequest) throws -> DopeCogResponse {
        try DopeCode.validateCode(req.code, field: "cog code")
        guard let scope = try dope.fetchDopeScope(uuid: req.scopeUuid) else {
            throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
        }
        let uuid = try core.insertBase(db, table: "dope_cog", extra: [
            "dope_scope_uuid": req.scopeUuid,
            "code": req.code, "name": req.name,
            "description": req.description ?? "",
            "sort_order": req.sortOrder ?? 0,
        ])
        let revision = try dope.bumpScopeRevision(
            scopeUuid: req.scopeUuid, area: .cogs, ownerUuid: uuid)
        try dope.recordDopeChange(scope: scope, action: "cog_add", level: nil,
                                  nodeUuid: uuid, revision: revision)
        return try fetchCogResponse(uuid: uuid, revision: revision)
    }

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
        try core.updateBase(db, table: "dope_cog", uuid: req.uuid,
                            expectedVersion: req.expectedVersion, set: set)
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid, area: .cogs, ownerUuid: req.uuid)
        try dope.recordDopeChange(scope: scope, action: "cog_update", level: nil,
                                  nodeUuid: req.uuid, revision: revision)
        return try fetchCogResponse(uuid: req.uuid, revision: revision)
    }

    func dopeCogDelete(_ req: DopeCogDeleteRequest) throws -> DopeCogDeleteResponse {
        let scope = try cogOwningScope(cogUuid: req.uuid)
        let elements = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM dope_cog_element WHERE dope_cog_uuid = ?
            """, arguments: [req.uuid]) ?? 0

        if req.soft == true {
            guard scope.tier?.isOverlay == true else {
                throw StoreError.badRequest(
                    detail: "--soft is only valid inside a masking scope; scope "
                          + "\(scope.uuid) is \(scope.scopeType)")
            }
            try core.updateBase(db, table: "dope_cog", uuid: req.uuid,
                                expectedVersion: req.expectedVersion,
                                set: ["deleted_on": Store.isoNow()])
        } else {
            try core.deleteBase(db, table: "dope_cog", uuid: req.uuid,
                                expectedVersion: req.expectedVersion)
        }
        let revision = try dope.bumpScopeRevision(scopeUuid: scope.uuid)
        try dope.recordDopeChange(scope: scope, action: "cog_delete", level: nil,
                                  nodeUuid: req.uuid, revision: revision)
        return DopeCogDeleteResponse(deletedUuid: req.uuid, cascadedElements: elements,
                                     scopeUuid: scope.uuid, revision: revision)
    }

    // MARK: - Elements

    func dopeCogElementAdd(
        _ req: DopeCogElementAddRequest
    ) throws -> DopeCogElementResponse {
        try DopeCode.validateCode(req.code, field: "cog element code")
        let spec = try DopeCogElementSpec.spec(for: req.elementType)
        guard try Row.fetchOne(db, sql: "SELECT uuid FROM dope_cog WHERE uuid = ?",
                               arguments: [req.cogUuid]) != nil else {
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
                      + " and cannot be top-level")
        case (.some(let parent), _):
            guard let parentType = try String.fetchOne(db, sql: """
                SELECT element_type FROM dope_cog_element WHERE uuid = ?
                """, arguments: [parent]) else {
                throw StoreError.notFound(entity: "dope_cog_element", key: parent)
            }
            guard let allowed = spec.allowedParentTypes,
                  allowed.contains(where: { $0.rawValue == parentType }) else {
                throw StoreError.badRequest(
                    detail: "element type '\(spec.type.rawValue)' is top-level only "
                          + "and cannot be parented under '\(parentType)'")
            }
        case (nil, nil):
            break  // top-level type at top level
        }

        // Spec-driven, not a literal special case: this was a hardcoded
        // primary_path check back when one type existed and its only
        // owned field happened to also be its only required one.
        // PersistenceOwner has no primary_path at all, so a per-type
        // requiredFields loop is what lets a second type exist.
        var subtypeValues: [String: (any DatabaseValueConvertible)?] = [:]
        for field in spec.requiredFields.sorted(by: { $0.rawValue < $1.rawValue }) {
            let supplied: String?
            switch field {
            case .primaryPath:         supplied = req.primaryPath
            case .dopePersistenceCode: supplied = req.dopePersistenceCode
            case .dopeScopeCode:       supplied = req.dopeScopeCode
            }
            guard let value = supplied, !value.isEmpty else {
                throw StoreError.badRequest(
                    detail: "element type '\(spec.type.rawValue)' requires --"
                          + field.rawValue.replacingOccurrences(
                                of: "([a-z0-9])([A-Z])", with: "$1-$2",
                                options: .regularExpression).lowercased())
            }
            subtypeValues[field.dbColumn] = value
        }

        let uuid = try core.insertBase(db, table: "dope_cog_element", extra: [
            "dope_cog_uuid": req.cogUuid,
            "parent_element_uuid": req.parentElementUuid,
            "element_type": spec.type.rawValue,
            "code": req.code, "name": req.name,
            "description": req.description ?? "",
            "sort_order": req.sortOrder ?? 0,
            "dope_scope_code": req.dopeScopeCode,
        ])
        subtypeValues["element_uuid"] = uuid
        _ = try core.insertBase(db, table: spec.subtypeTable, extra: subtypeValues)
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid, area: .cogs, ownerUuid: req.cogUuid)
        try dope.recordDopeChange(scope: scope, action: "cog_element_add", level: nil,
                                  nodeUuid: uuid, revision: revision)
        return try fetchCogElementResponse(uuid: uuid, revision: revision)
    }

    func dopeCogElementUpdate(
        _ req: DopeCogElementUpdateRequest
    ) throws -> DopeCogElementResponse {
        guard let typeRaw = try String.fetchOne(db, sql: """
            SELECT element_type FROM dope_cog_element WHERE uuid = ?
            """, arguments: [req.uuid]) else {
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
                    detail: "element type '\(typeRaw)' does not own --primary-path")
            }
            try db.execute(sql: """
                UPDATE \(spec.subtypeTable) SET primary_path = ?, updated_at = ?
                 WHERE element_uuid = ?
                """, arguments: [primaryPath, Store.isoNow(), req.uuid])
        } else if set.isEmpty {
            throw StoreError.emptyUpdate(entity: "dope_cog_element")
        }

        if !set.isEmpty {
            try core.updateBase(db, table: "dope_cog_element", uuid: req.uuid,
                                expectedVersion: req.expectedVersion, set: set)
        }
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid, area: .cogs,
            ownerUuid: try owningCogUuid(elementUuid: req.uuid))
        try dope.recordDopeChange(scope: scope, action: "cog_element_update", level: nil,
                                  nodeUuid: req.uuid, revision: revision)
        return try fetchCogElementResponse(uuid: req.uuid, revision: revision)
    }

    func dopeCogElementDelete(
        _ req: DopeCogElementDeleteRequest
    ) throws -> DopeCogDeleteResponse {
        let scope = try elementOwningScope(elementUuid: req.uuid)
        // Captured BEFORE the delete — a hard delete removes the row this
        // lookup reads, and the area counter still has to be advanced.
        let cogUuid = try owningCogUuid(elementUuid: req.uuid)
        let children = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM dope_cog_element WHERE parent_element_uuid = ?
            """, arguments: [req.uuid]) ?? 0
        if req.soft == true {
            guard scope.tier?.isOverlay == true else {
                throw StoreError.badRequest(
                    detail: "--soft is only valid inside a masking scope; scope "
                          + "\(scope.uuid) is \(scope.scopeType)")
            }
            try core.updateBase(db, table: "dope_cog_element", uuid: req.uuid,
                                expectedVersion: req.expectedVersion,
                                set: ["deleted_on": Store.isoNow()])
        } else {
            try core.deleteBase(db, table: "dope_cog_element", uuid: req.uuid,
                                expectedVersion: req.expectedVersion)
        }
        let revision = try dope.bumpScopeRevision(
            scopeUuid: scope.uuid, area: .cogs,
            ownerUuid: cogUuid)
        try dope.recordDopeChange(scope: scope, action: "cog_element_delete", level: nil,
                                  nodeUuid: req.uuid, revision: revision)
        return DopeCogDeleteResponse(deletedUuid: req.uuid, cascadedElements: children,
                                     scopeUuid: scope.uuid, revision: revision)
    }

    // MARK: - Read

    func dopeCogGet(_ req: DopeCogGetRequest) throws -> DopeCogGetResponse {
        guard try dope.fetchDopeScope(uuid: req.scopeUuid) != nil else {
            throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
        }
        var sql = "SELECT * FROM dope_cog WHERE dope_scope_uuid = ?"
        var args: [(any DatabaseValueConvertible)?] = [req.scopeUuid]
        if let code = req.code {
            sql += " AND code = ?"
            args.append(code)
        }
        sql += " ORDER BY sort_order, code"
        let cogs = try DopeCogRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        return DopeCogGetResponse(cogs: try cogs.map { row in
            try hydrateCog(row: row)
        })
    }

    /// Every cog of a scope, hydrated, for callers already inside a
    /// transaction — the repo write path needs cogs alongside the
    /// persistence tree. Extracted from dopeCogGet rather than duplicated.
    func fetchDopeCogs(scopeUuid: String) throws -> [DopeCogNode] {
        let rows = try DopeCogRecord.fetchAll(
            db, where: "dope_scope_uuid = ?", arguments: [scopeUuid],
            orderBy: "sort_order, code")
        return try rows.map { try hydrateCog(row: $0) }
    }

    // MARK: - Helpers

    private func cogOwningScope(cogUuid: String) throws -> DopeScopeRow {
        guard let row = try DopeScopeRecord.fetchOne(db, sql: """
            SELECT s.* FROM dope_scope s
            JOIN dope_cog c ON c.dope_scope_uuid = s.uuid
            WHERE c.uuid = ?
            """, arguments: [cogUuid]) else {
            throw StoreError.notFound(entity: "dope_cog", key: cogUuid)
        }
        return row.wireRow()
    }

    private func owningCogUuid(elementUuid: String) throws -> String {
        guard let uuid = try String.fetchOne(db, sql: """
            SELECT dope_cog_uuid FROM dope_cog_element WHERE uuid = ?
            """, arguments: [elementUuid]) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return uuid
    }

    private func elementOwningScope(elementUuid: String) throws -> DopeScopeRow {
        guard let row = try DopeScopeRecord.fetchOne(db, sql: """
            SELECT s.* FROM dope_scope s
            JOIN dope_cog c ON c.dope_scope_uuid = s.uuid
            JOIN dope_cog_element e ON e.dope_cog_uuid = c.uuid
            WHERE e.uuid = ?
            """, arguments: [elementUuid]) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: elementUuid)
        }
        return row.wireRow()
    }

    private func hydrateCog(row: DopeCogRecord) throws -> DopeCogNode {
        let elements = try DopeCogElementRecord.fetchAll(
            db, where: "dope_cog_uuid = ?", arguments: [row.uuid],
            orderBy: "sort_order, code")
        return DopeCogNode(
            uuid: row.uuid, version: row.version, code: row.code, name: row.name,
            description: row.description, sortOrder: Int(row.sortOrder),
            deletedOn: row.deletedOn,
            elements: try elements.map { try hydrateElement(row: $0) })
    }

    private func hydrateElement(row: DopeCogElementRecord) throws -> DopeCogElementNode {
        let spec = try DopeCogElementSpec.spec(for: row.elementType)
        // Spec-driven, like the writer: the subtype table's columns differ
        // per type, so selecting primary_path unconditionally would throw
        // "no such column" the moment a second type existed.
        //
        // THIS one stays on Row, and it is the documented floor of the Record
        // conversion: both the table (spec.subtypeTable) and the column
        // (field.dbColumn) are computed at runtime from the cog spec, which no
        // static Record type can express. It is the last hasColumn() in the
        // Database layer.
        let subtype = try Row.fetchOne(db, sql: """
            SELECT * FROM \(spec.subtypeTable) WHERE element_uuid = ?
            """, arguments: [row.uuid])
        func subtypeValue(_ field: DopeCogField) -> String? {
            guard spec.ownedFields.contains(field), let subtype,
                  subtype.hasColumn(field.dbColumn) else { return nil }
            return subtype[field.dbColumn]
        }
        return DopeCogElementNode(
            uuid: row.uuid, version: row.version, elementType: row.elementType,
            code: row.code, name: row.name, description: row.description,
            sortOrder: Int(row.sortOrder), parentElementUuid: row.parentElementUuid,
            dopeScopeCode: row.dopeScopeCode,
            primaryPath: subtypeValue(.primaryPath),
            dopePersistenceCode: subtypeValue(.dopePersistenceCode),
            deletedOn: row.deletedOn)
    }

    private func fetchCogResponse(
        uuid: String, revision: Int64
    ) throws -> DopeCogResponse {
        guard let row = try DopeCogRecord.fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: "dope_cog", key: uuid)
        }
        return DopeCogResponse(cog: try hydrateCog(row: row), revision: revision)
    }

    private func fetchCogElementResponse(
        uuid: String, revision: Int64
    ) throws -> DopeCogElementResponse {
        guard let row = try DopeCogElementRecord.fetch(db, uuid: uuid) else {
            throw StoreError.notFound(entity: "dope_cog_element", key: uuid)
        }
        return DopeCogElementResponse(element: try hydrateElement(row: row),
                                      revision: revision)
    }
}
