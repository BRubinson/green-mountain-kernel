import Foundation

/// Pure whole-bundle validation — no db, no filesystem. Collects EVERY
/// failure and throws once with a numbered list: an agent fixing a large
/// hand-edited tree needs the whole list, not one error per round trip.
public enum DopeValidator {

    public struct BundleError: Error, CustomStringConvertible, Sendable {
        public let errors: [String]
        public var description: String {
            "dope bundle invalid (\(errors.count) error\(errors.count == 1 ? "" : "s")):\n"
                + errors.enumerated().map { "  \($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
        }
    }

    /// Validates codes, description limits, sibling uniqueness, version
    /// agreement, the main domain map, data_type coupling, and full ref
    /// resolvability. Returns normally only on a fully consistent bundle.
    public static func validate(_ bundle: DopeDocumentBundle) throws {
        var errors: [String] = []

        func check(_ block: () throws -> Void) {
            do { try block() } catch { errors.append(String(describing: error)) }
        }

        // Scope.
        check { try DopeCode.validateCode(bundle.main.scope.code, field: "scope code") }
        // scope_type is no longer persisted, so there is nothing to
        // validate: only a SESSION_INSTANCE tree can be written to a repo
        // (Store.requireRepoWritableScope), which makes the field a constant
        // and a stored constant only creates the possibility of a file that
        // contradicts it. An older file that still carries scope_type simply
        // decodes with the key ignored.
        if bundle.main.version < 0 {
            errors.append("scope version \(bundle.main.version) is negative")
        }
        if bundle.main.scope.description.count > 512 {
            errors.append("scope description exceeds 512 characters")
        }

        // Main map ↔ domain files, 1:1, with re-derived paths.
        let fileCodes = bundle.domainFiles.map(\.body.code)
        let dupFileCodes = Dictionary(grouping: fileCodes, by: { $0 }).filter { $1.count > 1 }.keys
        for code in dupFileCodes.sorted() {
            errors.append("duplicate domain file for code '\(code)'")
        }
        let mapCodes = Set(bundle.main.persistence.keys)
        for code in mapCodes.subtracting(fileCodes).sorted() {
            errors.append(
                "\(DopeDocumentCodec.scopeFileName) names persistence '\(code)' but no domain was provided")
        }
        for code in Set(fileCodes).subtracting(mapCodes).sorted() {
            errors.append(
                "persistence domain '\(code)' is not named in \(DopeDocumentCodec.scopeFileName)")
        }
        for (code, path) in bundle.main.persistence.sorted(by: { $0.key < $1.key })
        where path != DopeScopeDocument.expectedFile(forPersistenceCode: code) {
            errors.append(
                "\(DopeDocumentCodec.scopeFileName) maps persistence '\(code)' to '\(path)' — expected '\(DopeScopeDocument.expectedFile(forPersistenceCode: code))' (the map is data, never followed)")
        }

        // Per-domain walks + the cross-domain ref indexes.
        var enumIndex = Set<String>()            // "domain.enums.enum"
        var propertyIndex = [String: String]()   // "domain.entity.property" → data_type
        var entityIndex = [String: String]()     // "domain.entity" → entity_type

        for file in bundle.domainFiles {
            let dcode = file.body.code
            check { try DopeCode.validateCode(dcode, field: "domain code") }
            if file.version != bundle.main.version {
                errors.append(
                    "domain '\(dcode)' carries version \(file.version) but \(DopeDocumentCodec.scopeFileName) says \(bundle.main.version) — hand-edit suspected")
            }
            if file.body.description.count > 512 {
                errors.append("domain '\(dcode)' description exceeds 512 characters")
            }

            var entityCodes = Set<String>()
            for entity in file.entities {
                let ecode = entity.body.code
                check { try DopeCode.validateCode(ecode, field: "entity code") }
                if ecode == DopeCode.reservedEnumSegment {
                    errors.append(
                        "domain '\(dcode)' has an entity coded 'enums' — reserved (it is what makes a.b.c and a.enums.b.c parseable)")
                }
                if !entityCodes.insert(ecode).inserted {
                    errors.append("domain '\(dcode)' has duplicate entity code '\(ecode)'")
                }
                if DopeEntityType(rawValue: entity.body.entityType) == nil {
                    errors.append(
                        "entity '\(dcode).\(ecode)' entity_type '\(entity.body.entityType)' is not MODEL, JUNCTION or BASE_COMPOSABLE")
                }
                entityIndex["\(dcode).\(ecode)"] = entity.body.entityType
                if entity.body.description.count > 512 {
                    errors.append("entity '\(dcode).\(ecode)' description exceeds 512 characters")
                }
                var propertyCodes = Set<String>()
                for property in entity.properties {
                    let pcode = property.body.code
                    check { try DopeCode.validateCode(pcode, field: "property code") }
                    if !propertyCodes.insert(pcode).inserted {
                        errors.append("entity '\(dcode).\(ecode)' has duplicate property code '\(pcode)'")
                    }
                    if property.body.description.count > 128 {
                        errors.append("property '\(dcode).\(ecode).\(pcode)' description exceeds 128 characters")
                    }
                    propertyIndex["\(dcode).\(ecode).\(pcode)"] = property.body.dataType
                }
            }

            var enumCodes = Set<String>()
            for en in file.enums {
                let ncode = en.body.code
                check { try DopeCode.validateCode(ncode, field: "enum code") }
                if !enumCodes.insert(ncode).inserted {
                    errors.append("domain '\(dcode)' has duplicate enum code '\(ncode)'")
                }
                if en.body.description.count > 256 {
                    errors.append("enum '\(dcode).enums.\(ncode)' description exceeds 256 characters")
                }
                enumIndex.insert(DopeCode.formatEnumRef(domain: dcode, enumCode: ncode))
                var optionCodes = Set<String>()
                for option in en.options {
                    let ocode = option.body.code
                    check { try DopeCode.validateCode(ocode, field: "option code") }
                    if !optionCodes.insert(ocode).inserted {
                        errors.append("enum '\(dcode).enums.\(ncode)' has duplicate option code '\(ocode)'")
                    }
                    if option.body.description.count > 128 {
                        errors.append("option '\(dcode).enums.\(ncode).\(ocode)' description exceeds 128 characters")
                    }
                }
            }
        }

        // Base-composable refs, now that entityIndex is complete (refs may
        // point forward and across domains). Surviving edges feed the cycle
        // check below.
        var baseEdge = [String: String]()        // "domain.entity" → target path
        for file in bundle.domainFiles {
            for entity in file.entities {
                let path = "\(file.body.code).\(entity.body.code)"
                guard let raw = entity.body.baseComposableRef else { continue }
                do {
                    _ = try DopeCode.parseEntityRef(
                        raw, field: "entity '\(path)' base_composable_ref")
                } catch {
                    errors.append(String(describing: error))
                    continue
                }
                if raw == path {
                    errors.append("entity '\(path)' composes itself")
                    continue
                }
                guard let targetType = entityIndex[raw] else {
                    errors.append("entity '\(path)' base_composable_ref '\(raw)' does not resolve")
                    continue
                }
                guard targetType == DopeEntityType.baseComposable.rawValue else {
                    errors.append(
                        "entity '\(path)' base_composable_ref '\(raw)' targets a \(targetType) — only a BASE_COMPOSABLE may be composed")
                    continue
                }
                baseEdge[path] = raw
            }
        }

        // Cycle check. Chaining is ALLOWED (a BASE_COMPOSABLE may itself
        // compose one), so the ban is on cycles, not on depth. Each entity
        // has at most ONE outgoing edge — the graph is functional — so this
        // is a linear pointer-chase with a three-colour map, never a
        // branching DFS.
        var colour = [String: Int]()             // 1 = on the current chase, 2 = settled
        for start in baseEdge.keys.sorted() where colour[start] == nil {
            var chain: [String] = []
            var node = start
            while colour[node] == nil, let next = baseEdge[node] {
                colour[node] = 1
                chain.append(node)
                node = next
            }
            if colour[node] == 1, let i = chain.firstIndex(of: node) {
                errors.append("base_composable cycle: "
                    + (chain[i...] + [node]).joined(separator: " → "))
            }
            for n in chain { colour[n] = 2 }
            colour[node] = 2
        }

        // Property shape coupling + ref resolution, now that the indexes are
        // complete (refs may point forward and across domains).
        for file in bundle.domainFiles {
            for entity in file.entities {
                for property in entity.properties {
                    let path = "\(file.body.code).\(entity.body.code).\(property.body.code)"
                    let body = property.body
                    guard let dataType = DopePropertyDataType(rawValue: body.dataType) else {
                        errors.append("property '\(path)' data_type '\(body.dataType)' is not a known type")
                        continue
                    }
                    let isEnum = dataType == .enumeration
                    let isRelationship = dataType == .relationship
                    if isEnum != (body.enumRef != nil) {
                        errors.append(
                            "property '\(path)': enum_ref must be present exactly when data_type is 'enum'")
                    }
                    if isRelationship != (body.relationshipTargetRef != nil) {
                        errors.append(
                            "property '\(path)': relationship_target_ref must be present exactly when data_type is 'relationship'")
                    }
                    if body.autoIncrement != nil && dataType != .long {
                        errors.append("property '\(path)': auto_increment is only legal on 'long'")
                    }
                    if body.textCharLimit != nil && dataType != .text {
                        errors.append("property '\(path)': text_char_limit is only legal on 'text'")
                    }
                    if let raw = body.enumRef {
                        do {
                            let ref = try DopeCode.parseRef(raw, field: "property '\(path)' enum_ref")
                            guard case .enumType = ref else {
                                throw DopeCode.ValidationError(
                                    "property '\(path)' enum_ref '\(raw)' is not a domain.enums.enum_code path")
                            }
                            if !enumIndex.contains(raw) {
                                errors.append("property '\(path)' enum_ref '\(raw)' does not resolve")
                            }
                        } catch { errors.append(String(describing: error)) }
                    }
                    if let raw = body.relationshipTargetRef {
                        do {
                            let ref = try DopeCode.parseRef(raw, field: "property '\(path)' relationship_target_ref")
                            guard case .property = ref else {
                                throw DopeCode.ValidationError(
                                    "property '\(path)' relationship_target_ref '\(raw)' is not a domain.entity.property path")
                            }
                            guard let targetType = propertyIndex[raw] else {
                                errors.append("property '\(path)' relationship_target_ref '\(raw)' does not resolve")
                                continue
                            }
                            // The spec's rule: the target property's type IS
                            // this column's value. A relationship targeting a
                            // relationship would recurse — rejected, which
                            // also makes insert dependency order acyclic.
                            if targetType == DopePropertyDataType.relationship.rawValue {
                                errors.append(
                                    "property '\(path)' targets '\(raw)', which is itself a relationship — chain refs are not allowed")
                            }
                        } catch { errors.append(String(describing: error)) }
                    }
                    if let raw = body.baseOriginRef {
                        do {
                            let ref = try DopeCode.parseRef(raw, field: "property '\(path)' base_origin_ref")
                            guard case let .property(originDomain, originEntityCode, _) = ref else {
                                throw DopeCode.ValidationError(
                                    "property '\(path)' base_origin_ref '\(raw)' is not a domain.entity.property path")
                            }
                            guard let originType = propertyIndex[raw] else {
                                errors.append("property '\(path)' base_origin_ref '\(raw)' does not resolve")
                                continue
                            }
                            let originEntity = DopeCode.formatEntityRef(
                                domain: originDomain, entity: originEntityCode)
                            guard entityIndex[originEntity] == DopeEntityType.baseComposable.rawValue else {
                                errors.append(
                                    "property '\(path)' base_origin_ref '\(raw)' originates from '\(originEntity)', which is not a BASE_COMPOSABLE")
                                continue
                            }
                            // Materialization is only legal DOWN a composition
                            // chain. Bounded walk with a visited set: a cyclic
                            // tree is already an error above, and errors are
                            // COLLECTED here, so this must not hang.
                            let ownEntity = "\(file.body.code).\(entity.body.code)"
                            var seen: Set<String> = [ownEntity]
                            var cursor = baseEdge[ownEntity]
                            while let node = cursor, node != originEntity, seen.insert(node).inserted {
                                cursor = baseEdge[node]
                            }
                            guard cursor == originEntity else {
                                errors.append(
                                    "property '\(path)' base_origin_ref '\(raw)': '\(ownEntity)' does not compose '\(originEntity)'")
                                continue
                            }
                            if originType != body.dataType {
                                errors.append(
                                    "property '\(path)' base_origin_ref '\(raw)': data_type '\(body.dataType)' differs from the origin's '\(originType)'")
                            }
                        } catch { errors.append(String(describing: error)) }
                    }
                }
            }
        }

        if !errors.isEmpty { throw BundleError(errors: errors) }
    }

    /// Wire-tree variant: project and validate the identity-free shape.
    public static func validate(_ tree: DopeScopeTree) throws {
        try validate(DopeProjection.documents(from: tree))
    }
}
