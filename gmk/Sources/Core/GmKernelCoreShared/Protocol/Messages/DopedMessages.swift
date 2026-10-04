import Foundation

// DOPE wire payloads, one MARK section per message family. All types are
// let-only structs on a Codable/Hashable/Sendable floor, no force-unwraps.
// snake_case comes from WireCodec's key strategies — types declare NO CodingKeys
// (the two intentional renames live in Envelope.swift; see WireCodec for the rule).
// Read-side row DTOs live in Rows.swift.

// MARK: - DOPE_*

/// Create-or-return a dope scope (idempotent, the archOpen precedent).
/// scope_type is derived: PROMPT when promptUuid is present, else
/// SESSION_INSTANCE. `cloneFromSessionBase` forks the session's
/// SESSION_INSTANCE tree of the same code into a freshly created PROMPT scope.
struct DopeInitRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let promptUuid: String?
    let code: String
    let name: String
    let description: String?
    let cloneFromSessionBase: Bool?

    /// Creates a DOPE_INIT request to create or return a dope scope.
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - code: The scope code identifier.
    ///   - name: The scope name.
    ///   - promptUuid: The prompt uuid for PROMPT-tier scope; nil for SESSION_INSTANCE.
    ///   - description: Optional description of the scope.
    ///   - cloneFromSessionBase: True to fork the session's SESSION_INSTANCE tree into the new PROMPT scope.
    init(
        sessionUuid: String,
        code: String,
        name: String,
        promptUuid: String? = nil,
        description: String? = nil,
        cloneFromSessionBase: Bool? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.name = name
        self.description = description
        self.cloneFromSessionBase = cloneFromSessionBase
    }
}

struct DopeScopeResponse: Codable, Hashable, Sendable {
    let scope: DopeScopeRow
    let created: Bool

    /// Creates a DOPE_INIT or DOPE-related response with the scope row.
    /// - Parameters:
    ///   - scope: The dope scope row.
    ///   - created: True if this call created the scope; false if it existed.
    init(scope: DopeScopeRow, created: Bool) {
        self.scope = scope
        self.created = created
    }
}

/// Scope enumeration for pickers.
///
/// Without promptUuid: the session's SESSION_INSTANCE scopes. With it: ONLY that prompt's PROMPT scopes — never a
/// union, so a GUI never string-parses dopeGet's "several dope scopes match" BAD_REQUEST. Unknown session/prompt uuid
/// is NOT_FOUND; a real target with no scopes is a normal empty list, never SUMMARY_ABSENT. No code filter: enumerating
/// IS the point and every row carries its own code.
struct DopeListRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let promptUuid: String?

    /// Creates a DOPE_LIST request to enumerate dope scopes.
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - promptUuid: The prompt uuid to list PROMPT scopes; nil for SESSION_INSTANCE scopes.
    init(sessionUuid: String, promptUuid: String? = nil) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
    }
}

struct DopeListResponse: Codable, Hashable, Sendable {
    /// ORDER BY code — the SAME order dopeGet's candidate list prints, so a
    /// picker's rows and the disambiguator message can never disagree.
    let scopes: [DopeScopeRow]

    /// Creates a DOPE_LIST response with the enumerated scope rows.
    /// - Parameter scopes: The dope scope rows ordered by code.
    init(scopes: [DopeScopeRow]) {
        self.scopes = scopes
    }
}

/// Tree read.
///
/// With promptUuid set, the PROMPT scope is preferred and the SESSION_INSTANCE tree is the fallback (resolvedVia
/// reports which). With several scopes matching and no code, the store answers BAD_REQUEST naming the candidate codes.
struct DopeGetRequest: Codable, Hashable, Sendable {
    /// Empty ONLY when addressing by `projectUuid` instead.
    ///
    /// Kept non-optional so every existing caller and every older peer's
    /// payload still decodes unchanged — a project-tier read passes "" here
    /// and fills `projectUuid`. Making it Optional would have been a
    /// breaking shape change on an existing message for no gain.
    let sessionUuid: String
    let promptUuid: String?
    let code: String?
    /// PROJECT-tier addressing: reads the PROJECT_ITEM overlay, else the
    /// BASE_PROJECT scope that `gm dope promote` maintains.
    ///
    /// Additive OPTIONAL, so no wire bump: an older peer omits it and gets
    /// exactly today's session-only behavior.
    let projectUuid: String?
    /// Merge the masking overlay over its base and return the resolved tree.
    ///
    /// OPT-IN, and deliberately so: without it every existing caller — the CLI, GMVibes, gm diagram from-dope, the
    /// screenshot path — keeps its exact single-layer semantics. Additive OPTIONAL, so an older peer that omits it
    /// means "unresolved", which is today's behavior.
    let resolved: Bool?

    /// Creates a DOPE_GET request to fetch a dope scope tree.
    /// - Parameters:
    ///   - sessionUuid: The session uuid; empty string for PROJECT-tier addressing.
    ///   - promptUuid: The prompt uuid for PROMPT-tier scope; nil for SESSION_INSTANCE fallback.
    ///   - code: The scope code; nil to handle disambiguation or use default.
    ///   - resolved: True to merge overlay over base and return resolved tree; nil for unresolved.
    ///   - projectUuid: The project uuid for PROJECT-tier addressing; nil for session-tier.
    init(
        sessionUuid: String,
        promptUuid: String? = nil,
        code: String? = nil,
        resolved: Bool? = nil,
        projectUuid: String? = nil
    ) {
        self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    /// Creates a DOPE_GET request for PROJECT-tier addressing.
    /// - Parameters:
    ///   - projectUuid: The project uuid to read its scope ladder.
    ///   - code: The scope code; nil for default.
    ///   - resolved: True to merge overlay over base; nil for unresolved.
    init(projectUuid: String, code: String? = nil, resolved: Bool? = nil) {
        self.sessionUuid = ""
        self.promptUuid = nil
        self.code = code
        self.resolved = resolved
        self.projectUuid = projectUuid
    }

    private enum CodingKeys: String, CodingKey {
        case sessionUuid, promptUuid, code, resolved, projectUuid
    }

    /// Decodes a dope search result from a keyed container, providing defaults for missing keys.
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Decoding errors from the container.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionUuid = try c.decodeIfPresent(String.self, forKey: .sessionUuid) ?? ""
        promptUuid = try c.decodeIfPresent(String.self, forKey: .promptUuid)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        resolved = try c.decodeIfPresent(Bool.self, forKey: .resolved)
        projectUuid = try c.decodeIfPresent(String.self, forKey: .projectUuid)
    }
}

struct DopeGetResponse: Codable, Hashable, Sendable {
    let tree: DopeScopeTree
    /// Which scope supplied the tree: "prompt" | "session_base", or
    /// "<overlay_tier>_over_<base_tier>" when --resolved merged two layers.
    let resolvedVia: String
    /// Present only for a resolved read: dot-path -> provenance.
    let resolutions: [DopeOverlay.Resolution]?
    /// Dot-paths a whiteout masked away.
    let hidden: [String]?
    /// Non-fatal observations (orphaned masks).
    ///
    /// Never an error.
    let warnings: [String]?
    /// Per-area content counters ("persistence", "cogs").
    ///
    /// A client compares one number to decide whether that subtree needs refetching, which is what makes dope
    /// sub-LOADABLE. These sit BESIDE tree.revision, which remains the whole-tree counter and the sole CAS gate.
    let areaVersions: [String: Int64]?

    /// Creates a DOPE_GET response with the scope tree and optional metadata.
    /// - Parameters:
    ///   - tree: The dope scope tree.
    ///   - resolvedVia: The scope that supplied the tree (prompt, session_base, or merged tiers).
    ///   - resolutions: Provenance mapping for resolved overlays; nil for non-resolved reads.
    ///   - hidden: Whiteout dot-paths that were masked away; nil if none.
    ///   - warnings: Non-fatal observations like orphaned masks; nil if none.
    ///   - areaVersions: Per-area content counters for change detection; nil if not relevant.
    init(
        tree: DopeScopeTree,
        resolvedVia: String,
        resolutions: [DopeOverlay.Resolution]? = nil,
        hidden: [String]? = nil,
        warnings: [String]? = nil,
        areaVersions: [String: Int64]? = nil
    ) {
        self.tree = tree
        self.resolvedVia = resolvedVia
        self.resolutions = resolutions
        self.hidden = hidden
        self.warnings = warnings
        self.areaVersions = areaVersions
    }
}

// MARK: - DOPE_SEARCH

/// The three search scopes, in the prompt's own vocabulary.
enum DopeSearchScope: String, Codable, Hashable, CaseIterable, Sendable {
    case prompt, session, project
}

/// One UNION arm per source table.
enum DopeSearchSource: String, Codable, Hashable, CaseIterable, Sendable {
    case scope, persistence, entity, property, enumeration, option, cog, cogElement
}

struct DopeSearchRequest: Codable, Hashable, Sendable {
    let query: String
    let scope: DopeSearchScope
    let sessionUuid: String?
    let promptUuid: String?
    let projectUuid: String?
    /// Keep only hits whose dot-path came from the overlay rather than the
    /// base.
    ///
    /// A post-filter over resolver provenance, so the FTS query is the same shape with and without it.
    let onlyMasks: Bool?
    /// Restrict the UNION to these arms. m0028-era ADDITIVE OPTIONAL: nil or
    /// empty means every arm, which is exactly what the absent field meant, so
    /// it decodes safely in both directions and needed no wire bump of its own.
    ///
    /// The arms were always enumerable through `DopeSearchSource`; what was
    /// missing was any way for a caller to SELECT among them, which is what the
    /// agent tool surface needs when it asks for persistence rows or cogs
    /// specifically rather than the whole tree.
    let sources: [DopeSearchSource]?
    let limit: Int?

    /// Creates a DOPE_SEARCH request to find dope entities by keyword.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - scope: The search scope (prompt, session, or project).
    ///   - sessionUuid: Filter to one session; nil to search all.
    ///   - promptUuid: Filter to one prompt; nil to search all.
    ///   - projectUuid: Filter to one project; nil to search all.
    ///   - onlyMasks: Filter to overlay-sourced hits; nil for all sources.
    ///   - sources: Restrict the search to these entity types; nil or empty for all.
    ///   - limit: Maximum results to return; nil for no limit.
    init(
        query: String,
        scope: DopeSearchScope,
        sessionUuid: String? = nil,
        promptUuid: String? = nil,
        projectUuid: String? = nil,
        onlyMasks: Bool? = nil,
        sources: [DopeSearchSource]? = nil,
        limit: Int? = nil
    ) {
        self.query = query; self.scope = scope; self.sessionUuid = sessionUuid
        self.promptUuid = promptUuid; self.projectUuid = projectUuid
        self.onlyMasks = onlyMasks; self.sources = sources; self.limit = limit
    }
}

struct DopeSearchHit: Codable, Hashable, Sendable {
    let kind: String
    let subjectUuid: String
    let scopeUuid: String
    let scopeCode: String
    let scopeType: String
    /// The dot-path — the same identity the resolver merges on.
    let path: String
    let title: String
    let excerpt: String
    let score: Double
    /// Resolver provenance; present only for an --only-masks search.
    let origin: String?

    /// Creates a search hit result.
    /// - Parameters:
    ///   - kind: The entity kind (scope, persistence, entity, property, etc.).
    ///   - subjectUuid: The uuid of the found entity.
    ///   - scopeUuid: The uuid of the scope containing the entity.
    ///   - scopeCode: The code of the scope.
    ///   - scopeType: The type of the scope (prompt, session, or project).
    ///   - path: The dot-path of the entity.
    ///   - title: The entity title or name.
    ///   - excerpt: A text excerpt showing context.
    ///   - score: The search relevance score.
    ///   - origin: Provenance layer; nil unless filtered by --only-masks.
    init(
        kind: String,
        subjectUuid: String,
        scopeUuid: String,
        scopeCode: String,
        scopeType: String,
        path: String,
        title: String,
        excerpt: String,
        score: Double,
        origin: String?
    ) {
        self.kind = kind; self.subjectUuid = subjectUuid; self.scopeUuid = scopeUuid
        self.scopeCode = scopeCode; self.scopeType = scopeType; self.path = path
        self.title = title; self.excerpt = excerpt; self.score = score; self.origin = origin
    }
}

struct DopeSearchResponse: Codable, Hashable, Sendable {
    let hits: [DopeSearchHit]

    /// Creates a DOPE_SEARCH response with the search results.
    /// - Parameter hits: The search hits found.
    init(hits: [DopeSearchHit]) { self.hits = hits }
}

// MARK: - COGS

struct DopeCogElementNode: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let elementType: String
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let parentElementUuid: String?
    /// Ghost-tolerant CODE reference to a dope scope, resolved at read time —
    /// never a uuid FK (ingest re-mints uuids, and scope delete is not
    /// offered, so there is no ON DELETE answer to give).
    let dopeScopeCode: String?
    /// From the type's subtype table.
    ///
    /// Hull only.
    let primaryPath: String?
    /// From the type's subtype table.
    ///
    /// PersistenceOwner only: the CODE of the persistence domain this element's parent Hull owns. Additive and
    /// OPTIONAL, so it decodes safely in both directions.
    let dopePersistenceCode: String?
    let deletedOn: String?

    /// Creates a cog element node representing a part of a cog hierarchy.
    /// - Parameters:
    ///   - uuid: The element uuid.
    ///   - version: The element version for optimistic locking.
    ///   - elementType: The element type (Hull, PersistenceOwner, etc.).
    ///   - code: The element code identifier.
    ///   - name: The element name.
    ///   - description: The element description.
    ///   - sortOrder: The display sort order.
    ///   - parentElementUuid: The parent element uuid; nil if root.
    ///   - dopeScopeCode: Ghost-tolerant reference to a dope scope; nil if not applicable.
    ///   - primaryPath: The primary path for Hull elements; nil for others.
    ///   - deletedOn: Timestamp if soft-deleted; nil if active.
    ///   - dopePersistenceCode: Owned persistence domain code for PersistenceOwner; nil otherwise.
    init(
        uuid: String,
        version: Int64,
        elementType: String,
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        parentElementUuid: String?,
        dopeScopeCode: String?,
        primaryPath: String?,
        deletedOn: String?,
        dopePersistenceCode: String? = nil
    ) {
        self.uuid = uuid
        self.version = version
        self.elementType = elementType
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.parentElementUuid = parentElementUuid
        self.dopeScopeCode = dopeScopeCode
        self.primaryPath = primaryPath
        self.dopePersistenceCode = dopePersistenceCode
        self.deletedOn = deletedOn
    }
}

struct DopeCogNode: Codable, Hashable, Sendable {
    let uuid: String
    let version: Int64
    let code: String
    let name: String
    let description: String
    let sortOrder: Int
    let deletedOn: String?
    let elements: [DopeCogElementNode]

    /// Creates a cog node representing a cog in a dope scope.
    /// - Parameters:
    ///   - uuid: The cog uuid.
    ///   - version: The cog version for optimistic locking.
    ///   - code: The cog code identifier.
    ///   - name: The cog name.
    ///   - description: The cog description.
    ///   - sortOrder: The display sort order.
    ///   - deletedOn: Timestamp if soft-deleted; nil if active.
    ///   - elements: The child element nodes.
    init(
        uuid: String,
        version: Int64,
        code: String,
        name: String,
        description: String,
        sortOrder: Int,
        deletedOn: String?,
        elements: [DopeCogElementNode]
    ) {
        self.uuid = uuid
        self.version = version
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.deletedOn = deletedOn
        self.elements = elements
    }
}

struct DopeCogAddRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let code: String
    let name: String
    let description: String?
    let sortOrder: Int?

    /// Creates a DOPE_COG_ADD request to create a new cog in a scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to add the cog to.
    ///   - code: The cog code identifier.
    ///   - name: The cog name.
    ///   - description: The cog description; nil if none.
    ///   - sortOrder: The display sort order; nil for default.
    init(
        scopeUuid: String,
        code: String,
        name: String,
        description: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.scopeUuid = scopeUuid; self.code = code; self.name = name
        self.description = description; self.sortOrder = sortOrder
    }
}

struct DopeCogUpdateRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?

    /// Creates a DOPE_COG_UPDATE request to modify a cog's properties.
    /// - Parameters:
    ///   - uuid: The cog uuid to update.
    ///   - expectedVersion: The expected cog version.
    ///   - code: New code identifier; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    init(
        uuid: String,
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
    }
}

struct DopeCogDeleteRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let soft: Bool?

    /// Creates a DOPE_COG_DELETE request to remove or soft-delete a cog.
    /// - Parameters:
    ///   - uuid: The cog uuid to delete.
    ///   - expectedVersion: The expected cog version.
    ///   - soft: True for soft-delete (timestamped); false for hard delete; nil for default.
    init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

struct DopeCogElementAddRequest: Codable, Hashable, Sendable {
    let cogUuid: String
    let elementType: String
    let code: String
    let name: String
    let description: String?
    let sortOrder: Int?
    let parentElementUuid: String?
    let dopeScopeCode: String?
    let primaryPath: String?
    /// PersistenceOwner's owned domain CODE.
    ///
    /// Additive and OPTIONAL, so it decodes safely in both directions per the wire convention.
    let dopePersistenceCode: String?

    /// Creates a DOPE_COG_ELEMENT_ADD request to add an element to a cog.
    /// - Parameters:
    ///   - cogUuid: The cog uuid to add the element to.
    ///   - elementType: The element type (Hull, PersistenceOwner, etc.).
    ///   - code: The element code identifier.
    ///   - name: The element name.
    ///   - description: The element description; nil if none.
    ///   - sortOrder: The display sort order; nil for default.
    ///   - parentElementUuid: Parent element uuid; nil if root.
    ///   - dopeScopeCode: Ghost-tolerant dope scope reference; nil if not applicable.
    ///   - primaryPath: Primary path for Hull elements; nil for other types.
    ///   - dopePersistenceCode: Owned persistence domain code; nil for non-PersistenceOwner.
    init(
        cogUuid: String,
        elementType: String,
        code: String,
        name: String,
        description: String? = nil,
        sortOrder: Int? = nil,
        parentElementUuid: String? = nil,
        dopeScopeCode: String? = nil,
        primaryPath: String? = nil,
        dopePersistenceCode: String? = nil
    ) {
        self.cogUuid = cogUuid; self.elementType = elementType; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.parentElementUuid = parentElementUuid; self.dopeScopeCode = dopeScopeCode
        self.primaryPath = primaryPath; self.dopePersistenceCode = dopePersistenceCode
    }
}

struct DopeCogElementUpdateRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let dopeScopeCode: String?
    let clearDopeScopeCode: Bool?
    let primaryPath: String?

    /// Creates a DOPE_COG_ELEMENT_UPDATE request to modify a cog element.
    /// - Parameters:
    ///   - uuid: The element uuid to update.
    ///   - expectedVersion: The expected element version.
    ///   - code: New code identifier; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    ///   - dopeScopeCode: New dope scope reference; nil to leave unchanged.
    ///   - clearDopeScopeCode: True to clear the scope reference; nil to ignore.
    ///   - primaryPath: New primary path; nil to leave unchanged.
    init(
        uuid: String,
        expectedVersion: Int64,
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        dopeScopeCode: String? = nil,
        clearDopeScopeCode: Bool? = nil,
        primaryPath: String? = nil
    ) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.code = code
        self.name = name; self.description = description; self.sortOrder = sortOrder
        self.dopeScopeCode = dopeScopeCode; self.clearDopeScopeCode = clearDopeScopeCode
        self.primaryPath = primaryPath
    }
}

struct DopeCogElementDeleteRequest: Codable, Hashable, Sendable {
    let uuid: String
    let expectedVersion: Int64
    let soft: Bool?

    /// Creates a DOPE_COG_ELEMENT_DELETE request to remove or soft-delete a cog element.
    /// - Parameters:
    ///   - uuid: The element uuid to delete.
    ///   - expectedVersion: The expected element version.
    ///   - soft: True for soft-delete (timestamped); false for hard delete; nil for default.
    init(uuid: String, expectedVersion: Int64, soft: Bool? = nil) {
        self.uuid = uuid; self.expectedVersion = expectedVersion; self.soft = soft
    }
}

struct DopeCogGetRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let code: String?

    /// Creates a DOPE_COG_GET request to fetch cogs from a scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to query.
    ///   - code: Filter to one cog by code; nil to retrieve all.
    init(scopeUuid: String, code: String? = nil) {
        self.scopeUuid = scopeUuid; self.code = code
    }
}

struct DopeCogResponse: Codable, Hashable, Sendable {
    let cog: DopeCogNode
    let revision: Int64

    /// Creates a DOPE_COG response with the created or modified cog.
    /// - Parameters:
    ///   - cog: The cog node.
    ///   - revision: The scope revision after the operation.
    init(cog: DopeCogNode, revision: Int64) { self.cog = cog; self.revision = revision }
}

struct DopeCogElementResponse: Codable, Hashable, Sendable {
    let element: DopeCogElementNode
    let revision: Int64

    /// Creates a DOPE_COG_ELEMENT response with the created or modified element.
    /// - Parameters:
    ///   - element: The cog element node.
    ///   - revision: The scope revision after the operation.
    init(element: DopeCogElementNode, revision: Int64) {
        self.element = element; self.revision = revision
    }
}

struct DopeCogDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let cascadedElements: Int
    let scopeUuid: String
    let revision: Int64

    /// Creates a DOPE_COG_DELETE response with deletion results.
    /// - Parameters:
    ///   - deletedUuid: The uuid of the deleted cog.
    ///   - cascadedElements: The number of child elements cascade-deleted.
    ///   - scopeUuid: The scope uuid of the deleted cog.
    ///   - revision: The scope revision after the deletion.
    init(deletedUuid: String, cascadedElements: Int, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid; self.cascadedElements = cascadedElements
        self.scopeUuid = scopeUuid; self.revision = revision
    }
}

struct DopeCogGetResponse: Codable, Hashable, Sendable {
    let cogs: [DopeCogNode]

    /// Creates a DOPE_COG_GET response with the fetched cogs.
    /// - Parameter cogs: The cog nodes from the scope.
    init(cogs: [DopeCogNode]) { self.cogs = cogs }
}

/// DOPE_PROMOTE — publish a session's SESSION_INSTANCE tree into the
/// project's BASE_PROJECT scope.
///
/// Runs automatically at boot behind DopeBootSync, and manually via `gm dope promote` (a non-throwing boot path that
/// silently does nothing is undebuggable, so the verb exists too).
struct DopePromoteRequest: Codable, Hashable, Sendable {
    let sessionUuid: String
    let code: String?
    /// Compute the decision and write NOTHING.
    ///
    /// This is what makes "why didn't it promote?" answerable, and it is what gm doctor uses to report a stale
    /// BASE_PROJECT without ever publishing as a side effect.
    let dryRun: Bool?

    /// Creates a DOPE_PROMOTE request to publish a session's scope tree to the project base scope.
    /// - Parameters:
    ///   - sessionUuid: The session uuid to promote from.
    ///   - code: Filter to one scope; nil to promote all.
    ///   - dryRun: True to compute decision without writing; false or nil to publish.
    init(sessionUuid: String, code: String? = nil, dryRun: Bool? = nil) {
        self.sessionUuid = sessionUuid
        self.code = code
        self.dryRun = dryRun
    }
}

struct DopePromotedScope: Codable, Hashable, Sendable {
    let code: String
    let baseScopeUuid: String
    /// The high-water the base carried before this promotion.
    let fromRevision: Int64
    /// The source revision now recorded as the high-water.
    let toRevision: Int64
    let counts: DopeTreeCounts

    /// Creates a promoted scope record with revision and content details.
    /// - Parameters:
    ///   - code: The scope code.
    ///   - baseScopeUuid: The base scope uuid in the project.
    ///   - fromRevision: The base scope's revision before promotion.
    ///   - toRevision: The session scope revision promoted.
    ///   - counts: Entity count breakdown of the promoted tree.
    init(
        code: String,
        baseScopeUuid: String,
        fromRevision: Int64,
        toRevision: Int64,
        counts: DopeTreeCounts
    ) {
        self.code = code
        self.baseScopeUuid = baseScopeUuid
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.counts = counts
    }
}

struct DopePromoteResponse: Codable, Hashable, Sendable {
    /// On a dry run these are what WOULD be published, and nothing was
    /// written.
    let promoted: [DopePromotedScope]
    /// "branch_mismatch" | "no_session_scope" | "up_to_date" | nil.
    let skipped: String?
    let detail: String?

    /// Creates a DOPE_PROMOTE response with promotion results or skip reasons.
    /// - Parameters:
    ///   - promoted: The scopes that were promoted (empty on skip or dry run).
    ///   - skipped: Skip reason if promotion was not performed; nil if successful.
    ///   - detail: Additional context explaining the skip or operation result.
    init(promoted: [DopePromotedScope], skipped: String? = nil, detail: String? = nil) {
        self.promoted = promoted
        self.skipped = skipped
        self.detail = detail
    }
}

/// The generic node-mutation payload. nil = leave alone; the clear* flags
/// mean "set NULL" — a distinction plain optionals cannot express.
///
/// Which fields a level owns is DopeLevelSpec's ownedFields; a misdirected field is a precise BAD_REQUEST.
struct DopeNodeFields: Codable, Hashable, Sendable {
    let code: String?
    let name: String?
    let description: String?
    let sortOrder: Int?
    let entityType: DopeEntityType?
    let repoRepresentativeFile: String?
    let baseComposableUuid: String?
    let dataType: DopePropertyDataType?
    let nullable: Bool?
    let isUnique: Bool?
    let autoIncrement: Bool?
    let textCharLimit: Int?
    let enumUuid: String?
    let relationshipTargetUuid: String?
    let baseOriginPropertyUuid: String?
    let clearRepoRepresentativeFile: Bool?
    let clearBaseComposable: Bool?
    let clearBaseOrigin: Bool?
    let clearAutoIncrement: Bool?
    let clearTextCharLimit: Bool?
    let clearEnum: Bool?
    let clearRelationshipTarget: Bool?

    /// Creates generic node mutation fields; nil values leave fields unchanged; clear* flags set them NULL.
    /// - Parameters:
    ///   - code: New code; nil to leave unchanged.
    ///   - name: New name; nil to leave unchanged.
    ///   - description: New description; nil to leave unchanged.
    ///   - sortOrder: New sort order; nil to leave unchanged.
    ///   - entityType: New entity type; nil to leave unchanged.
    ///   - repoRepresentativeFile: New file path; nil to leave unchanged.
    ///   - baseComposableUuid: New base composable uuid; nil to leave unchanged.
    ///   - dataType: New property data type; nil to leave unchanged.
    ///   - nullable: New nullability flag; nil to leave unchanged.
    ///   - isUnique: New uniqueness flag; nil to leave unchanged.
    ///   - autoIncrement: New autoincrement flag; nil to leave unchanged.
    ///   - textCharLimit: New character limit; nil to leave unchanged.
    ///   - enumUuid: New enum uuid; nil to leave unchanged.
    ///   - relationshipTargetUuid: New relationship target uuid; nil to leave unchanged.
    ///   - baseOriginPropertyUuid: New base origin uuid; nil to leave unchanged.
    ///   - clearRepoRepresentativeFile: True to set file path to NULL.
    ///   - clearBaseComposable: True to set base composable to NULL.
    ///   - clearBaseOrigin: True to set base origin to NULL.
    ///   - clearAutoIncrement: True to set autoincrement to NULL.
    ///   - clearTextCharLimit: True to set character limit to NULL.
    ///   - clearEnum: True to set enum to NULL.
    ///   - clearRelationshipTarget: True to set relationship target to NULL.
    init(
        code: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sortOrder: Int? = nil,
        entityType: DopeEntityType? = nil,
        repoRepresentativeFile: String? = nil,
        baseComposableUuid: String? = nil,
        dataType: DopePropertyDataType? = nil,
        nullable: Bool? = nil,
        isUnique: Bool? = nil,
        autoIncrement: Bool? = nil,
        textCharLimit: Int? = nil,
        enumUuid: String? = nil,
        relationshipTargetUuid: String? = nil,
        baseOriginPropertyUuid: String? = nil,
        clearRepoRepresentativeFile: Bool? = nil,
        clearBaseComposable: Bool? = nil,
        clearBaseOrigin: Bool? = nil,
        clearAutoIncrement: Bool? = nil,
        clearTextCharLimit: Bool? = nil,
        clearEnum: Bool? = nil,
        clearRelationshipTarget: Bool? = nil
    ) {
        self.code = code
        self.name = name
        self.description = description
        self.sortOrder = sortOrder
        self.entityType = entityType
        self.repoRepresentativeFile = repoRepresentativeFile
        self.baseComposableUuid = baseComposableUuid
        self.dataType = dataType
        self.nullable = nullable
        self.isUnique = isUnique
        self.autoIncrement = autoIncrement
        self.textCharLimit = textCharLimit
        self.enumUuid = enumUuid
        self.relationshipTargetUuid = relationshipTargetUuid
        self.baseOriginPropertyUuid = baseOriginPropertyUuid
        self.clearRepoRepresentativeFile = clearRepoRepresentativeFile
        self.clearBaseComposable = clearBaseComposable
        self.clearBaseOrigin = clearBaseOrigin
        self.clearAutoIncrement = clearAutoIncrement
        self.clearTextCharLimit = clearTextCharLimit
        self.clearEnum = clearEnum
        self.clearRelationshipTarget = clearRelationshipTarget
    }
}

struct DopeNodeAddRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let parentUuid: String
    let fields: DopeNodeFields

    /// Creates a DOPE_NODE_ADD request to insert a new dope entity.
    /// - Parameters:
    ///   - level: The dope level where the node belongs (scope, entity, property, etc.).
    ///   - parentUuid: The parent node uuid.
    ///   - fields: The node's field values.
    init(level: DopeLevel, parentUuid: String, fields: DopeNodeFields) {
        self.level = level
        self.parentUuid = parentUuid
        self.fields = fields
    }
}

struct DopeNodeUpdateRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let nodeUuid: String
    let expectedVersion: Int64
    let fields: DopeNodeFields

    /// Creates a DOPE_NODE_UPDATE request to modify a dope entity.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - nodeUuid: The node uuid to update.
    ///   - expectedVersion: The expected node version.
    ///   - fields: The field values to update.
    init(level: DopeLevel, nodeUuid: String, expectedVersion: Int64, fields: DopeNodeFields) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.fields = fields
    }
}

struct DopeNodeDeleteRequest: Codable, Hashable, Sendable {
    let level: DopeLevel
    let nodeUuid: String
    let expectedVersion: Int64
    /// Soft delete: stamp `deleted_on` instead of removing the row.
    ///
    /// The node stays visible to every read (that IS the feature — it communicates an intended delete), keeps
    /// satisfying every FK, and in an overlay tree acts as the resolver's whiteout over the base node at that dot-path.
    ///
    /// Additive OPTIONAL, so a peer that omits it still means "hard delete".
    let soft: Bool?

    /// Creates a DOPE_NODE_DELETE request to remove or soft-delete a dope entity.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - nodeUuid: The node uuid to delete.
    ///   - expectedVersion: The expected node version.
    ///   - soft: True for soft-delete (timestamped); nil or false for hard delete.
    init(
        level: DopeLevel,
        nodeUuid: String,
        expectedVersion: Int64,
        soft: Bool? = nil
    ) {
        self.level = level
        self.nodeUuid = nodeUuid
        self.expectedVersion = expectedVersion
        self.soft = soft
    }
}

struct DopeNodeResponse: Codable, Hashable, Sendable {
    let level: DopeLevel
    let uuid: String
    let version: Int64
    let scopeUuid: String
    /// The scope's whole-tree content counter after this mutation.
    let revision: Int64

    /// Creates a DOPE_NODE response with the created or modified node details.
    /// - Parameters:
    ///   - level: The dope level of the node.
    ///   - uuid: The node uuid.
    ///   - version: The node version after the operation.
    ///   - scopeUuid: The scope uuid containing the node.
    ///   - revision: The scope revision after the operation.
    init(level: DopeLevel, uuid: String, version: Int64, scopeUuid: String, revision: Int64) {
        self.level = level
        self.uuid = uuid
        self.version = version
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

struct DopeNodeDeleteResponse: Codable, Hashable, Sendable {
    let deletedUuid: String
    let cascaded: DopeTreeCounts
    let scopeUuid: String
    let revision: Int64

    /// Creates a DOPE_NODE_DELETE response with deletion results.
    /// - Parameters:
    ///   - deletedUuid: The uuid of the deleted node.
    ///   - cascaded: Count of cascade-deleted child nodes.
    ///   - scopeUuid: The scope uuid of the deleted node.
    ///   - revision: The scope revision after the deletion.
    init(deletedUuid: String, cascaded: DopeTreeCounts, scopeUuid: String, revision: Int64) {
        self.deletedUuid = deletedUuid
        self.cascaded = cascaded
        self.scopeUuid = scopeUuid
        self.revision = revision
    }
}

/// Parse + validate the on-disk tree.
///
/// Never writes. Exactly one of scopeUuid (resolve the scope's own instance root) or dirPath (an explicit instance root
/// — read-only, still required to be a git checkout) must be present.
struct DopeReadRepoRequest: Codable, Hashable, Sendable {
    let scopeUuid: String?
    let dirPath: String?

    /// Creates a DOPE_READ_REPO request to parse and validate a scope's on-disk tree.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to resolve its instance root; nil if dirPath is given.
    ///   - dirPath: Explicit instance root path; nil to use the scope's own.
    init(scopeUuid: String? = nil, dirPath: String? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
    }
}

struct DopeReadRepoResponse: Codable, Hashable, Sendable {
    let bundle: DopeDocumentBundle
    let onDiskRevision: Int64
    let dbRevision: Int64?
    let drift: Bool?
    let warnings: [String]

    /// Creates a DOPE_READ_REPO response with the parsed tree and version information.
    /// - Parameters:
    ///   - bundle: The parsed dope document bundle.
    ///   - onDiskRevision: The file version found on disk.
    ///   - dbRevision: The database revision; nil if not applicable.
    ///   - drift: True if on-disk and database revisions diverge.
    ///   - warnings: Non-fatal observations during parsing.
    init(
        bundle: DopeDocumentBundle,
        onDiskRevision: Int64,
        dbRevision: Int64?,
        drift: Bool?,
        warnings: [String]
    ) {
        self.bundle = bundle
        self.onDiskRevision = onDiskRevision
        self.dbRevision = dbRevision
        self.drift = drift
        self.warnings = warnings
    }
}

/// db → files.
///
/// Refuses when the on-disk version is AHEAD of the db revision (the files hold edits never ingested) unless force.
/// Does not modify the db beyond the audit event; does not bump revision (a projection, so a repeat run is
/// byte-idempotent).
struct DopeWriteRepoRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    let force: Bool?

    /// Creates a DOPE_WRITE_REPO request to write the database tree to files.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to write.
    ///   - force: True to overwrite when on-disk version is ahead; false or nil to refuse.
    init(scopeUuid: String, force: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.force = force
    }
}

struct DopeWriteRepoResponse: Codable, Hashable, Sendable {
    let dopeRoot: String
    let filesWritten: [String]
    let filesPruned: [String]
    let revision: Int64

    /// Creates a DOPE_WRITE_REPO response with the written files and result.
    /// - Parameters:
    ///   - dopeRoot: The root directory where files were written.
    ///   - filesWritten: Paths of files created or modified.
    ///   - filesPruned: Paths of files removed.
    ///   - revision: The database revision at write time.
    init(dopeRoot: String, filesWritten: [String], filesPruned: [String], revision: Int64) {
        self.dopeRoot = dopeRoot
        self.filesWritten = filesWritten
        self.filesPruned = filesPruned
        self.revision = revision
    }
}

/// files → db, whole-tree overwrite (no smart diff): the on-disk version
/// must equal db revision + 1 exactly.
///
/// Every child uuid changes on every ingest — the locked consequence of uuid-free JSON.
struct DopeIngestRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// Explicit instance root to read from; nil = the scope's own.
    let dirPath: String?
    /// Files-are-authoritative mode (boot sync only): permits any strictly
    /// FORWARD move (on-disk version > db revision), including seeding a
    /// virgin scope at revision 0 from a tree at any version.
    ///
    /// Never moves backward. Additive optional — absent means the strict +1 gate.
    let adopt: Bool?

    /// Creates a DOPE_INGEST request to parse files and update the database scope.
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to ingest into.
    ///   - dirPath: Explicit instance root path; nil to use the scope's own.
    ///   - adopt: True for files-are-authoritative mode (boot sync); nil for strict +1.
    init(scopeUuid: String, dirPath: String? = nil, adopt: Bool? = nil) {
        self.scopeUuid = scopeUuid
        self.dirPath = dirPath
        self.adopt = adopt
    }
}

struct DopeIngestResponse: Codable, Hashable, Sendable {
    let scope: DopeScopeRow
    let counts: DopeTreeCounts
    /// Revision the scope held before this ingest (additive optional).
    let previousRevision: Int64?
    /// Revisions skipped beyond the strict +1 step (adopt only, additive).
    let gapCrossed: Int64?

    /// Creates a DOPE_INGEST response with the updated scope and entity counts.
    /// - Parameters:
    ///   - scope: The scope row after ingestion.
    ///   - counts: Entity counts in the ingested tree.
    ///   - previousRevision: The scope's revision before ingestion (additive optional).
    ///   - gapCrossed: Revisions skipped in adopt mode; nil in strict mode.
    init(
        scope: DopeScopeRow,
        counts: DopeTreeCounts,
        previousRevision: Int64? = nil,
        gapCrossed: Int64? = nil
    ) {
        self.scope = scope
        self.counts = counts
        self.previousRevision = previousRevision
        self.gapCrossed = gapCrossed
    }
}

// MARK: - Dope merge / resolve

/// DOPE_MERGE_PLAN — the per-element boundary plan for one scope.
///
/// Read-only.
struct DopeMergePlanRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// Creates a DOPE_MERGE_PLAN request.
    /// - Parameter scopeUuid: The scope's unique identifier.
    init(scopeUuid: String) { self.scopeUuid = scopeUuid }
}

struct DopeMergeOutcomeRow: Codable, Hashable, Sendable {
    let dotPath: String
    let kind: String
    let decision: String
    /// Creates a merge outcome row for one boundary.
    /// - Parameters:
    ///   - dotPath: The dotted path of the element.
    ///   - kind: The element kind.
    ///   - decision: The merge decision for this element.
    init(dotPath: String, kind: String, decision: String) {
        self.dotPath = dotPath
        self.kind = kind
        self.decision = decision
    }
}

struct DopeMergePlanResponse: Codable, Hashable, Sendable {
    let outcomes: [DopeMergeOutcomeRow]
    let conflictCount: Int
    /// Creates a DOPE_MERGE_PLAN response.
    /// - Parameters:
    ///   - outcomes: The merge outcome rows for each boundary element.
    ///   - conflictCount: The count of conflicting dot-paths.
    init(outcomes: [DopeMergeOutcomeRow], conflictCount: Int) {
        self.outcomes = outcomes
        self.conflictCount = conflictCount
    }
}

/// DOPE_RESOLVE — settle conflicting dot-paths in one direction.
struct DopeResolveRequest: Codable, Hashable, Sendable {
    let scopeUuid: String
    /// nil = every unresolved conflict.
    let dotPath: String?
    /// true keeps the db side, false takes the file side.
    let takeOurs: Bool
    /// Creates a DOPE_RESOLVE request.
    /// - Parameters:
    ///   - scopeUuid: The scope's unique identifier.
    ///   - takeOurs: True keeps the db side, false takes the file side.
    ///   - dotPath: The specific dot-path to resolve; nil resolves all unresolved conflicts.
    init(scopeUuid: String, takeOurs: Bool, dotPath: String? = nil) {
        self.scopeUuid = scopeUuid
        self.dotPath = dotPath
        self.takeOurs = takeOurs
    }
}

struct DopeResolveResponse: Codable, Hashable, Sendable {
    let resolved: [String]
    let takeOurs: Bool
    /// Creates a DOPE_RESOLVE response.
    /// - Parameters:
    ///   - resolved: The dot-paths that were resolved.
    ///   - takeOurs: True if the db side was kept, false if the file side was taken.
    init(resolved: [String], takeOurs: Bool) {
        self.resolved = resolved
        self.takeOurs = takeOurs
    }
}
