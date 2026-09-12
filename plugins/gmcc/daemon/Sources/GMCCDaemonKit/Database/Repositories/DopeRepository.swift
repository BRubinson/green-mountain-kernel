import Foundation
import GRDB

/// DOPED domain modeling data access — scope lifecycle, tree hydration, and
/// the generic per-level node mutations. Whole-tree repo verbs live in
/// Store+DopeRepo. Runs INSIDE a Store-owned transaction; holds no dbQueue
/// and never self-transacts. Internal helpers keep their explicit `db`
/// parameter — verbatim moves from the Store extension.
///
/// Two counters, deliberately split (the touchSession precedent): every row's
/// `version` stays THE optimistic lock, while `dope_scope.revision` is the
/// whole-tree content counter (= the .doped.json version field), advanced by
/// `bumpScopeRevision` WITHOUT touching the scope row's version — a property
/// edit deep in the tree must never invalidate a dope_scope version a
/// GMVibes scope editor is holding.
struct DopeRepository: RepositoryContext {
    let db: Database
    let core: StoreCore


    // MARK: - Level description limits (pre-validated for friendly errors;
    // the schema CHECKs are the backstop)

    private static let dopeDescriptionLimits: [DopeLevel: Int] = [
        .scope: 512, .persistence: 512, .entity: 512,
        .enumeration: 256, .option: 128, .property: 128,
    ]

    // MARK: - Row + scope helpers

    func fetchDopeScope(uuid: String) throws -> DopeScopeRow? {
        try DopeScopeRecord.fetchOne(db, sql: "SELECT * FROM dope_scope WHERE uuid = ?", arguments: [uuid])
            .map { $0.wireRow() }
    }


    /// Advance the whole-tree content counter WITHOUT bumping the scope row's
    /// version — see the extension doc comment and StoreCore.touchSession.
    /// `area` additionally advances that subtree's own content counter, which
    /// is what makes dope sub-LOADABLE: a client compares one area's number
    /// instead of refetching the whole tree.
    ///
    /// dope_scope.revision REMAINS the single whole-tree counter and the sole
    /// CAS gate for read-repo / write-repo / ingest. The area counters sit
    /// BESIDE it and never replace it — splitting the scalar, as the goal
    /// originally read, would invalidate all three gates and the version field
    /// in every committed .doped.json at once, for a signal this already gives.
    @discardableResult
    func bumpScopeRevision(
        scopeUuid: String, area: DopeArea? = nil, ownerUuid: String? = nil
    ) throws -> Int64 {
        if let area, let ownerUuid {
            try db.execute(sql: """
                UPDATE \(area.table) SET content_revision = content_revision + 1, updated_at = ?
                 WHERE uuid = ?
                """, arguments: [Store.isoNow(), ownerUuid])
        }
        try db.execute(
            sql: "UPDATE dope_scope SET revision = revision + 1, updated_at = ? WHERE uuid = ?",
            arguments: [Store.isoNow(), scopeUuid])
        guard let revision = try Int64.fetchOne(
            db, sql: "SELECT revision FROM dope_scope WHERE uuid = ?", arguments: [scopeUuid]
        ) else {
            throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
        }
        return revision
    }

    /// Session-keyed twin of the promptUuid variant in Store+Architecture —
    /// dope's repo verbs are scope-addressed and scopes hang off sessions.
    func instanceRoot(sessionUuid: String) throws -> String {
        try String.fetchOne(db, sql: """
            SELECT i.absolute_file_system_path
            FROM session s
            JOIN instance i ON i.uuid = s.instance_uuid
            WHERE s.uuid = ?
            """, arguments: [sessionUuid]) ?? ""
    }

    /// Resolve the scope that owns a node at `level`. The join chains are the
    /// registry's parent links spelled out as SQL.
    func dopeOwningScope(level: DopeLevel, nodeUuid: String) throws -> DopeScopeRow {
        let sql: String
        switch level {
        case .scope:
            sql = "SELECT s.* FROM dope_scope s WHERE s.uuid = ?"
        case .persistence:
            sql = """
                SELECT s.* FROM dope_persistence d
                JOIN dope_scope s ON s.uuid = d.dope_scope_uuid WHERE d.uuid = ?
                """
        case .entity:
            sql = """
                SELECT s.* FROM dope_persistence_entity e
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_scope s ON s.uuid = d.dope_scope_uuid WHERE e.uuid = ?
                """
        case .property:
            sql = """
                SELECT s.* FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_scope s ON s.uuid = d.dope_scope_uuid WHERE p.uuid = ?
                """
        case .enumeration:
            sql = """
                SELECT s.* FROM dope_persistence_enum n
                JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                JOIN dope_scope s ON s.uuid = d.dope_scope_uuid WHERE n.uuid = ?
                """
        case .option:
            sql = """
                SELECT s.* FROM dope_persistence_enum_option o
                JOIN dope_persistence_enum n ON n.uuid = o.dope_persistence_enum_uuid
                JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
                JOIN dope_scope s ON s.uuid = d.dope_scope_uuid WHERE o.uuid = ?
                """
        }
        guard let row = try DopeScopeRecord.fetchOne(db, sql: sql, arguments: [nodeUuid]) else {
            throw StoreError.notFound(
                entity: DopeLevelSpec.spec(for: level).table, key: nodeUuid)
        }
        return row.wireRow()
    }

    // internal: the promotion machine emits DOPE_CHANGE too.
    func recordDopeChange(
        scope: DopeScopeRow, action: String, level: DopeLevel?,
        nodeUuid: String?, revision: Int64
    ) throws {
        // Every granular mutation funnels through here, which makes it the
        // one place the merge base learns that this session touched an
        // element. Addressed by dot-path, because ingest re-mints uuids.
        if let level, let nodeUuid, level != .scope {
            if let dotPath = try dopeProvenance.dotPath(nodeUuid: nodeUuid, level: level) {
                try dopeProvenance.markLocallyModified(scopeUuid: scope.uuid,
                                        dotPath: dotPath, kind: level.rawValue)
            }
        }
        // A project-tier scope (BASE_PROJECT / PROJECT_ITEM) has no session,
        // so the event carries the key only when there is one to carry, and
        // there is no session activity to touch below.
        var payload: [String: Any] = [
            "action": action,
            "scope_uuid": scope.uuid,
            "scope_type": scope.scopeType,
            "revision": Int(revision),
        ]
        if let sessionUuid = scope.sessionUuid { payload["session_uuid"] = sessionUuid }
        if let projectUuid = scope.projectUuid.isEmpty ? nil : scope.projectUuid {
            payload["project_uuid"] = projectUuid
        }
        if let level { payload["level"] = level.rawValue }
        if let nodeUuid { payload["node_uuid"] = nodeUuid }
        if let promptUuid = scope.promptUuid { payload["prompt_uuid"] = promptUuid }
        try core.appendEvent(db, kind: .dopeChange, subjectUuid: scope.uuid,
                        payload: Store.jsonPayload(payload))
        if let sessionUuid = scope.sessionUuid {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    // MARK: - Read-time staleness (shared by agent_briefing and care_package)

    /// The read-time drift report BOTH agent_briefing and care_package need.
    /// Compare a stamped scope revision against the live one, re-resolve every
    /// dot-path. Warn, never block. Computed, never stored.
    ///
    /// `drifted` deliberately keeps the guard-both-sides semantics this moved
    /// out of BriefingRepository: a MISSING number on either side is not
    /// evidence of drift (an unstamped ref set, or a scope row that no longer
    /// exists, both report `false`). Loosening that to a bare `!=` would flip
    /// the badge on for every never-stamped briefing.
    func scopeStaleness(
        scopeUuid: String?, stampedRevision: Int64?, dotPaths: [String]
    ) throws -> (stamped: Int64?, current: Int64?, drifted: Bool, ghosts: [String]) {
        // No scope -> no drift, no ghosts.
        guard let scopeUuid else { return (stampedRevision, nil, false, []) }
        let current = try Int64.fetchOne(
            db, sql: "SELECT revision FROM dope_scope WHERE uuid = ?", arguments: [scopeUuid])
        let drifted: Bool = {
            guard let stamped = stampedRevision, let current else { return false }
            return stamped != current
        }()
        var ghosts: [String] = []
        for path in dotPaths where try !dotPathExists(scopeUuid: scopeUuid, path: path) {
            ghosts.append(path)
        }
        return (stampedRevision, current, drifted, ghosts)
    }

    /// Dot-path existence check for ghost reporting. Forms accepted:
    /// domain · domain.entity · domain.entity.property ·
    /// domain.enums.enum_code · domain.enums.enum_code.option_code.
    /// Anything unparseable is simply a ghost — never an error.
    ///
    /// MOVED VERBATIM from BriefingRepository (was `private func
    /// dopeDotPathExists`): dope_persistence* is THIS repository's table set,
    /// and RepositoryContext's own doc comment prescribes naming the owner.
    func dotPathExists(scopeUuid: String, path: String) throws -> Bool {
        let segs = path.split(separator: ".").map(String.init)
        guard !segs.isEmpty, segs.count <= 4 else { return false }
        guard let persistenceUuid = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM dope_persistence WHERE dope_scope_uuid = ? AND code = ?",
            arguments: [scopeUuid, segs[0]]
        ) else { return false }
        if segs.count == 1 { return true }

        if segs[1] == "enums" {
            guard segs.count >= 3 else { return false }
            guard let enumUuid = try String.fetchOne(
                db,
                sql: "SELECT uuid FROM dope_persistence_enum WHERE dope_persistence_uuid = ? AND code = ?",
                arguments: [persistenceUuid, segs[2]]
            ) else { return false }
            if segs.count == 3 { return true }
            return try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM dope_persistence_enum_option WHERE dope_persistence_enum_uuid = ? AND code = ?",
                arguments: [enumUuid, segs[3]]
            ) != nil
        }

        guard let entityUuid = try String.fetchOne(
            db,
            sql: "SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ? AND code = ?",
            arguments: [persistenceUuid, segs[1]]
        ) else { return false }
        if segs.count == 2 { return true }
        guard segs.count == 3 else { return false }
        return try Row.fetchOne(
            db,
            sql: "SELECT 1 FROM dope_persistence_entity_property WHERE dope_persistence_entity_uuid = ? AND code = ?",
            arguments: [entityUuid, segs[2]]
        ) != nil
    }

    // MARK: - Init

    func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        try DopeCode.validateCode(req.code, field: "scope code")
        let description = req.description ?? ""
        guard description.count <= 512 else {
            throw StoreError.badRequest(detail: "scope description exceeds 512 characters")
        }
        guard try Row.fetchOne(
            db, sql: "SELECT uuid FROM session WHERE uuid = ?", arguments: [req.sessionUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        if let promptUuid = req.promptUuid {
            guard let owner = try String.fetchOne(
                db, sql: "SELECT session_uuid FROM prompt WHERE uuid = ?",
                arguments: [promptUuid]
            ) else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            guard owner == req.sessionUuid else {
                throw StoreError.badRequest(
                    detail: "prompt \(promptUuid) does not belong to session \(req.sessionUuid)")
            }
        }

        let scopeType: DopeScopeType = req.promptUuid == nil ? .sessionInstance : .sessionInstanceItem
        let existingSql = req.promptUuid == nil
            ? "SELECT * FROM dope_scope WHERE session_uuid = ? AND scope_type = 'SESSION_INSTANCE' AND code = ?"
            : "SELECT * FROM dope_scope WHERE session_uuid = ? AND prompt_uuid = ? AND scope_type = 'SESSION_INSTANCE_ITEM' AND code = ?"
        let existingArgs: StatementArguments = req.promptUuid == nil
            ? [req.sessionUuid, req.code]
            : [req.sessionUuid, req.promptUuid, req.code]
        if let row = try DopeScopeRecord.fetchOne(db, sql: existingSql, arguments: existingArgs) {
            return DopeScopeResponse(scope: row.wireRow(), created: false)
        }

        // The chain-non-null tier ladder: a session-tier scope fills its
        // own FK and every ancestor uuid, so list/get by any ancestor stays
        // a plain indexed WHERE (m0010 grammar, ported by m0013).
        guard let lineage = try Row.fetchOne(
            db,
            sql: "SELECT i.project_uuid AS p, s.instance_uuid AS i FROM session s "
                + "JOIN instance i ON i.uuid = s.instance_uuid WHERE s.uuid = ?",
            arguments: [req.sessionUuid]
        ) else {
            throw StoreError.corruptState(
                entity: "session",
                detail: "session \(req.sessionUuid) has no instance->project lineage")
        }
        let uuid = try core.insertBase(db, table: "dope_scope", extra: [
            "project_uuid": lineage["p"] as String,
            "instance_uuid": lineage["i"] as String,
            "session_uuid": req.sessionUuid,
            "prompt_uuid": req.promptUuid,
            "scope_type": scopeType.rawValue,
            "code": req.code,
            "name": req.name,
            "description": description,
            "revision": 0,
        ])

        if req.cloneFromSessionBase == true {
            guard req.promptUuid != nil else {
                throw StoreError.badRequest(
                    detail: "--clone-from-session-base is only meaningful for a PROMPT scope")
            }
            guard let baseRow = try DopeScopeRecord.fetchOne(db, sql: """
                SELECT * FROM dope_scope
                WHERE session_uuid = ? AND scope_type = 'SESSION_INSTANCE' AND code = ?
                """, arguments: [req.sessionUuid, req.code]) else {
                throw StoreError.badRequest(
                    detail: "no SESSION_INSTANCE scope with code '\(req.code)' to clone from")
            }
            _ = try copyDopeTree(from: baseRow.wireRow(), into: uuid)
        }

        guard let scope = try fetchDopeScope(uuid: uuid) else {
            throw StoreError.corruptState(entity: "dope_scope", detail: "vanished after insert")
        }
        try recordDopeChange(scope: scope, action: "init", level: .scope,
                                  nodeUuid: uuid, revision: scope.revision)
        return DopeScopeResponse(scope: scope, created: true)
    }

    // MARK: - Read-verb guards + shared candidate query

    /// dopeInit's existence validation (minus the ownership check, a
    /// write-verb concern), hoisted so the read verbs can discriminate an
    /// unknown uuid (NOT_FOUND) from a real-but-uninitialized target
    /// (SUMMARY_ABSENT) — the clarify/arch/explore/review get pattern.
    private func requireDopeTarget(
        sessionUuid: String, promptUuid: String?
    ) throws {
        guard try Row.fetchOne(
            db, sql: "SELECT uuid FROM session WHERE uuid = ?", arguments: [sessionUuid]
        ) != nil else {
            throw StoreError.notFound(entity: "session", key: sessionUuid)
        }
        if let promptUuid {
            guard try Row.fetchOne(
                db, sql: "SELECT uuid FROM prompt WHERE uuid = ?", arguments: [promptUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
        }
    }

    /// The scope-candidate query shared by dopeGet's resolution ladder and
    /// dopeList's enumeration — one copy keeps the picker's row order and
    /// the BAD_REQUEST candidate order identical (ORDER BY code).
    // internal, not private: Store+Diagram's binding resolution reuses this
    // exact ladder query (the v12 candidates() promotion precedent).
    func dopeScopeCandidates(
        sessionUuid: String, scopeType: DopeScopeType,
        promptUuid: String? = nil, code: String? = nil
    ) throws -> [DopeScopeRow] {
        var sql = "SELECT * FROM dope_scope WHERE session_uuid = ? AND scope_type = ?"
        var args: [(any DatabaseValueConvertible)?] = [sessionUuid, scopeType.rawValue]
        if scopeType == .sessionInstanceItem {
            sql += " AND prompt_uuid = ?"
            args.append(promptUuid)
        }
        if let code {
            sql += " AND code = ?"
            args.append(code)
        }
        sql += " ORDER BY code"
        return try DopeScopeRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            .map { $0.wireRow() }
    }

    /// Project-tier scope candidates — the rung the ladder never had.
    ///
    /// `dopeScopeCandidates` is `WHERE session_uuid = ?`, so BASE_PROJECT
    /// scopes were unaddressable: DOPE_PROMOTE has been populating them
    /// all along and nothing could read one back. That was invisible while
    /// every diagram was session-owned, and becomes a wall the moment a
    /// PROJECT-tier diagram tries to bind a scope — it resolves nothing and
    /// renders as a canvas of ghosts, which looks like a UI bug and is not.
    ///
    /// PROJECT_ITEM is the masking tier over BASE_PROJECT, mirroring
    /// SESSION_INSTANCE_ITEM over SESSION_INSTANCE.
    func dopeProjectScopeCandidates(
        projectUuid: String, scopeType: DopeScopeType,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        var sql = """
            SELECT * FROM dope_scope
             WHERE project_uuid = ? AND scope_type = ? AND session_uuid IS NULL
            """
        var args: [(any DatabaseValueConvertible)?] = [projectUuid, scopeType.rawValue]
        if let code {
            sql += " AND code = ?"
            args.append(code)
        }
        sql += " ORDER BY code"
        return try DopeScopeRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            .map { $0.wireRow() }
    }

    // MARK: - List (v12; picker enumeration — never a PROMPT/SESSION_INSTANCE union)

    func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try requireDopeTarget(
            sessionUuid: req.sessionUuid, promptUuid: req.promptUuid)
        let scopes: [DopeScopeRow]
        if let promptUuid = req.promptUuid {
            scopes = try dopeScopeCandidates(
                sessionUuid: req.sessionUuid, scopeType: .sessionInstanceItem,
                promptUuid: promptUuid)
        } else {
            scopes = try dopeScopeCandidates(
                sessionUuid: req.sessionUuid, scopeType: .sessionInstance)
        }
        return DopeListResponse(scopes: scopes)
    }

    // MARK: - Get (PROMPT → SESSION_INSTANCE fallback)

    func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        func pick(_ rows: [DopeScopeRow]) throws -> DopeScopeRow? {
            if rows.count > 1 {
                throw StoreError.badRequest(detail:
                    "several dope scopes match — pass --code (candidates: "
                    + rows.map(\.code).joined(separator: ", ") + ")")
            }
            return rows.first
        }

        // PROJECT-tier addressing: its own two-rung ladder, mirroring
        // the session one. Reached by a project-tier diagram's bindings
        // and by a DOPE_GET carrying project_uuid.
        if let projectUuid = req.projectUuid {
            guard req.sessionUuid.isEmpty else {
                throw StoreError.badRequest(
                    detail: "pass --project-uuid OR --session-uuid, not both")
            }
            guard try Row.fetchOne(
                db, sql: "SELECT uuid FROM project WHERE uuid = ?",
                arguments: [projectUuid]) != nil else {
                throw StoreError.notFound(entity: "project", key: projectUuid)
            }
            var projectVia = "base_project"
            var found = try pick(try dopeProjectScopeCandidates(
                projectUuid: projectUuid, scopeType: .projectItem, code: req.code))
            if found != nil { projectVia = "project_item" }
            if found == nil {
                found = try pick(try dopeProjectScopeCandidates(
                    projectUuid: projectUuid, scopeType: .baseProject,
                    code: req.code))
            }
            guard let scope = found else {
                throw StoreError.dopeProjectScopeAbsent(
                    projectUuid: projectUuid, code: req.code)
            }
            return DopeGetResponse(
                tree: try fetchDopeTree(scope: scope),
                resolvedVia: projectVia)
        }

        try requireDopeTarget(
            sessionUuid: req.sessionUuid, promptUuid: req.promptUuid)

        var resolvedVia = "session_base"
        var scope: DopeScopeRow?
        if let promptUuid = req.promptUuid {
            scope = try pick(try dopeScopeCandidates(
                sessionUuid: req.sessionUuid, scopeType: .sessionInstanceItem,
                promptUuid: promptUuid, code: req.code))
            if scope != nil { resolvedVia = "prompt" }
        }
        if scope == nil {
            scope = try pick(try dopeScopeCandidates(
                sessionUuid: req.sessionUuid, scopeType: .sessionInstance,
                code: req.code))
        }
        guard let scope else {
            // The target exists (guard above) — this absence means
            // "initialize a scope", not "the uuid is unknown".
            throw StoreError.dopeScopeAbsent(
                sessionUuid: req.sessionUuid, promptUuid: req.promptUuid, code: req.code)
        }
        let tree = try fetchDopeTree(scope: scope)

        // Unresolved is the default and is byte-identical to pre-resolver
        // behavior — every existing caller is untouched.
        let areas = try areaVersions(scopeUuid: scope.uuid)

        guard req.resolved == true, let tier = scope.tier, tier.isOverlay,
              let baseTier = tier.masks else {
            return DopeGetResponse(tree: tree, resolvedVia: resolvedVia,
                                   areaVersions: areas)
        }

        // Base pairing is by CODE plus lineage, needing no stored pointer:
        // an overlay masks the same-coded scope one tier up. A missing
        // base is legal — the overlay resolves alone, warned.
        // Tier-aware: a SESSION_INSTANCE_ITEM masks its session's base,
        // but a PROJECT_ITEM masks a PROJECT-tier base that has no
        // session at all. Keying both off session_uuid would throw on the
        // project pair.
        let baseRows: [DopeScopeRow]
        if baseTier.isSessionOwned {
            baseRows = try dopeScopeCandidates(
                sessionUuid: try scope.requireSessionUuid(), scopeType: baseTier,
                code: scope.code)
        } else {
            baseRows = try DopeScopeRecord.fetchAll(db, sql: """
                SELECT * FROM dope_scope
                 WHERE project_uuid = ? AND scope_type = ? AND code = ?
                 ORDER BY code
                """, arguments: [scope.projectUuid, baseTier.rawValue, scope.code])
                .map { $0.wireRow() }
        }
        let baseTree = try baseRows.first.map { try fetchDopeTree(scope: $0) }
        let merged = DopeOverlay.resolve(base: baseTree, overlay: tree)
        return DopeGetResponse(
            tree: merged.tree,
            resolvedVia: "\(tier.rawValue.lowercased())_over_\(baseTier.rawValue.lowercased())",
            resolutions: merged.resolutions.values.sorted { $0.path < $1.path },
            hidden: merged.hidden.sorted(),
            warnings: merged.warnings,
            areaVersions: areas)
    }

    /// The dope_persistence row a node lives under — the persistence area's
    /// counter owner. Mirrors dopeOwningScope's join chain, stopping one level
    /// short.
    func owningPersistenceUuid(
        level: DopeLevel, nodeUuid: String
    ) throws -> String? {
        let sql: String
        switch level {
        case .scope: return nil
        case .persistence: return nodeUuid
        case .entity:
            sql = "SELECT dope_persistence_uuid FROM dope_persistence_entity WHERE uuid = ?"
        case .enumeration:
            sql = "SELECT dope_persistence_uuid FROM dope_persistence_enum WHERE uuid = ?"
        case .property:
            sql = """
                SELECT e.dope_persistence_uuid FROM dope_persistence_entity e
                JOIN dope_persistence_entity_property p
                  ON p.dope_persistence_entity_uuid = e.uuid
                WHERE p.uuid = ?
                """
        case .option:
            sql = """
                SELECT n.dope_persistence_uuid FROM dope_persistence_enum n
                JOIN dope_persistence_enum_option o ON o.dope_persistence_enum_uuid = n.uuid
                WHERE o.uuid = ?
                """
        }
        return try String.fetchOne(db, sql: sql, arguments: [nodeUuid])
    }

    /// Per-area content counters, derived as the max content_revision inside
    /// each area. Derived rather than stored on the scope: one fewer column to
    /// keep consistent, and the answer a client actually wants ("has anything
    /// in this area moved?") is exactly a max.
    func areaVersions(scopeUuid: String) throws -> [String: Int64] {
        var out = [String: Int64]()
        for area in DopeArea.allCases {
            out[area.rawValue] = try Int64.fetchOne(db, sql: """
                SELECT COALESCE(MAX(content_revision), 0) FROM \(area.table)
                 WHERE dope_scope_uuid = ?
                """, arguments: [scopeUuid]) ?? 0
        }
        return out
    }

    // MARK: - Hydration (five flat queries, grouped in Swift — never per-node
    // recursion; ORDER BY sort_order, code keeps write-repo deterministic)

    /// - Parameter forProjection: when true, every level filters
    ///   `deleted_on IS NULL`.
    ///
    ///   Reads deliberately return tombstoned rows — the masking resolver
    ///   NEEDS them, since a whiteout is only meaningful if you can see it.
    ///   The db → files projection must not: a tombstone is personal,
    ///   overlay-tier state, and a saved .doped.json is shared, committed
    ///   fact.
    ///
    ///   DEFENCE IN DEPTH, deliberately. Two independent gates already make
    ///   a tombstone unreachable from here: `dopeNodeDelete` refuses `--soft`
    ///   outside an overlay tier, and `requireRepoWritableScope` refuses any
    ///   repo verb outside SESSION_INSTANCE — disjoint sets, so no scope is
    ///   both soft-deletable and writable. This filter is what keeps that
    ///   true if either gate is ever relaxed: the invariant then holds
    ///   because the projection enforces it directly, not because two
    ///   unrelated guards happen to intersect at zero.
    ///
    ///   Defaults to false so every existing read keeps its behaviour; only
    ///   the write path opts in.
    func fetchDopeTree(
        scope: DopeScopeRow, forProjection: Bool = false
    ) throws -> DopeScopeTree {
        // Interpolated, not bound: this is a constant SQL fragment chosen by a
        // Bool, never user input.
        let live = forProjection ? "AND %@.deleted_on IS NULL" : ""
        func alive(_ alias: String) -> String {
            live.replacingOccurrences(of: "%@", with: alias)
        }
        let domainRows = try DopePersistenceRecord.fetchAll(db, sql: """
            SELECT * FROM dope_persistence WHERE dope_scope_uuid = ?
            \(forProjection ? "AND deleted_on IS NULL" : "")
            ORDER BY sort_order, code
            """, arguments: [scope.uuid])
        let entityRows = try DopePersistenceEntityRecord.fetchAll(db, sql: """
            SELECT e.* FROM dope_persistence_entity e
            JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
            WHERE d.dope_scope_uuid = ? \(alive("e")) \(alive("d"))
            ORDER BY e.sort_order, e.code
            """, arguments: [scope.uuid])
        let enumRows = try DopePersistenceEnumRecord.fetchAll(db, sql: """
            SELECT n.* FROM dope_persistence_enum n
            JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
            WHERE d.dope_scope_uuid = ? \(alive("n")) \(alive("d"))
            ORDER BY n.sort_order, n.code
            """, arguments: [scope.uuid])
        let optionRows = try DopePersistenceEnumOptionRecord.fetchAll(db, sql: """
            SELECT o.* FROM dope_persistence_enum_option o
            JOIN dope_persistence_enum n ON n.uuid = o.dope_persistence_enum_uuid
            JOIN dope_persistence d ON d.uuid = n.dope_persistence_uuid
            WHERE d.dope_scope_uuid = ? \(alive("o")) \(alive("n")) \(alive("d"))
            ORDER BY o.sort_order, o.code
            """, arguments: [scope.uuid])
        let propertyRows = try DopePersistenceEntityPropertyRecord.fetchAll(db, sql: """
            SELECT p.* FROM dope_persistence_entity_property p
            JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
            JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
            WHERE d.dope_scope_uuid = ? \(alive("p")) \(alive("e")) \(alive("d"))
            ORDER BY p.sort_order, p.code
            """, arguments: [scope.uuid])

        // Ref projection maps: uuid → dot-path code.
        var domainCode = [String: String]()
        for row in domainRows { domainCode[row.uuid] = row.code }
        var entityInfo = [String: (domain: String, code: String)]()
        var entityRef = [String: String]()
        for row in entityRows {
            let domain = domainCode[row.dopePersistenceUuid] ?? "?"
            entityInfo[row.uuid] = (domain, row.code)
            entityRef[row.uuid] = DopeCode.formatEntityRef(
                domain: domain, entity: row.code)
        }
        var enumRef = [String: String]()
        for row in enumRows {
            let domain = domainCode[row.dopePersistenceUuid] ?? "?"
            enumRef[row.uuid] = DopeCode.formatEnumRef(domain: domain, enumCode: row.code)
        }
        var propertyRef = [String: String]()
        for row in propertyRows {
            let info = entityInfo[row.dopePersistenceEntityUuid] ?? (domain: "?", code: "?")
            propertyRef[row.uuid] = DopeCode.formatPropertyRef(
                domain: info.domain, entity: info.code, property: row.code)
        }

        // One identity shape over five record types: every dope node table
        // carries the same BaseEntity columns plus deleted_on.
        func identity<R: DopeNodeRecord>(_ row: R) -> DopeNodeIdentity {
            DopeNodeIdentity(uuid: row.uuid, version: row.version,
                             createdAt: row.createdAt, updatedAt: row.updatedAt,
                             deletedOn: row.deletedOn)
        }

        var propertiesByEntity = [String: [DopePropertyNode]]()
        for row in propertyRows {
            let node = DopePropertyNode(
                identity: identity(row),
                body: DopePropertyBody(
                    code: row.code, name: row.name, description: row.description,
                    sortOrder: Int(row.sortOrder), dataType: row.dataType,
                    nullable: row.nullable,
                    isUnique: row.isUnique,
                    autoIncrement: row.autoIncrement,
                    textCharLimit: row.textCharLimit.map(Int.init),
                    enumRef: row.dopePersistenceEnumUuid.flatMap { enumRef[$0] },
                    relationshipTargetRef: row.relationshipTargetUuid
                        .flatMap { propertyRef[$0] },
                    baseOriginRef: row.baseOriginPropertyUuid
                        .flatMap { propertyRef[$0] }))
            propertiesByEntity[row.dopePersistenceEntityUuid, default: []].append(node)
        }
        var optionsByEnum = [String: [DopeOptionNode]]()
        for row in optionRows {
            optionsByEnum[row.dopePersistenceEnumUuid, default: []].append(
                DopeOptionNode(identity: identity(row),
                               body: DopeOptionBody(code: row.code, name: row.name,
                                                    description: row.description,
                                                    sortOrder: Int(row.sortOrder))))
        }
        var entitiesByDomain = [String: [DopeEntityNode]]()
        for row in entityRows {
            entitiesByDomain[row.dopePersistenceUuid, default: []].append(
                DopeEntityNode(identity: identity(row),
                               body: DopeEntityBody(
                                    code: row.code, name: row.name,
                                    entityType: row.entityType,
                                    description: row.description,
                                    sortOrder: Int(row.sortOrder),
                                    repoRepresentativeFile: row.repoRepresentativeFile,
                                    baseComposableRef: row.baseComposableUuid
                                        .flatMap { entityRef[$0] }),
                               properties: propertiesByEntity[row.uuid] ?? []))
        }
        var enumsByDomain = [String: [DopeEnumNode]]()
        for row in enumRows {
            enumsByDomain[row.dopePersistenceUuid, default: []].append(
                DopeEnumNode(identity: identity(row),
                             body: DopeEnumBody(
                                code: row.code, name: row.name,
                                description: row.description, sortOrder: Int(row.sortOrder),
                                repoRepresentativeFile: row.repoRepresentativeFile),
                             options: optionsByEnum[row.uuid] ?? []))
        }
        let domains = domainRows.map { row in
            DopePersistenceNode(identity: identity(row),
                           body: DopePersistenceBody(code: row.code, name: row.name,
                                                description: row.description,
                                                sortOrder: Int(row.sortOrder)),
                           entities: entitiesByDomain[row.uuid] ?? [],
                           enums: enumsByDomain[row.uuid] ?? [])
        }
        return DopeScopeTree(
            identity: DopeNodeIdentity(uuid: scope.uuid, version: scope.version,
                                       createdAt: scope.createdAt, updatedAt: scope.updatedAt),
            body: DopeScopeBody(code: scope.code, name: scope.name,
                                description: scope.description),
            sessionUuid: scope.sessionUuid, promptUuid: scope.promptUuid,
            scopeType: scope.scopeType, revision: scope.revision, domains: domains)
    }

    /// Whole-tree copy between scopes: hydrate, project to identity-free
    /// documents, re-insert. EXTRACTED verbatim from what dopeInit already
    /// inlined for --clone-from-session-base, so `dopeInit` and
    /// `dopePromote` share ONE copy path rather than growing a second.
    ///
    /// Child uuids are re-minted by insertDopeTree, which is exactly why
    /// cross-layer references are dot-path codes and never uuids.
    @discardableResult
    func copyDopeTree(
        from source: DopeScopeRow, into targetScopeUuid: String
    ) throws -> DopeTreeCounts {
        let tree = try fetchDopeTree(scope: source)
        let bundle = DopeProjection.documents(from: tree)
        return try insertDopeTree(scopeUuid: targetScopeUuid,
                                  domainFiles: bundle.domainFiles)
    }

    // MARK: - Whole-tree insert (clone + ingest share it). Documents in,
    // rows out; validator-approved input assumed (callers validate first).
    // Insert order is dependency order: domains → enums → options → entities
    // → non-relationship properties → relationship properties.

    @discardableResult
    func insertDopeTree(
        scopeUuid: String, domainFiles: [DopePersistenceFileDocument]
    ) throws -> DopeTreeCounts {
        var counts = (domains: 0, entities: 0, properties: 0, enums: 0, options: 0)
        var domainUuidByCode = [String: String]()
        var enumUuidByRef = [String: String]()
        var propertyUuidByRef = [String: String]()
        var entityUuidByRef = [String: String]()
        var entityRefByUuid = [String: String]()
        var pendingRelationship: [(entityUuid: String, body: DopePropertyBody)] = []
        var pendingBase: [(entityUuid: String, ref: String)] = []
        var pendingBaseOrigin: [(propertyUuid: String, ref: String)] = []

        // Pass 1 — ALL domains, then ALL enums + options, across every file
        // BEFORE any property is inserted: enum refs are cross-domain-capable
        // and domain files arrive in arbitrary (alphabetical) order, so a
        // per-domain forward pass would miss a ref into a later domain and
        // write NULL into a CHECK-coupled column.
        for file in domainFiles {
            let domainUuid = try core.insertBase(db, table: "dope_persistence", extra: [
                "dope_scope_uuid": scopeUuid,
                "code": file.body.code, "name": file.body.name,
                "description": file.body.description, "sort_order": file.body.sortOrder,
            ])
            counts.domains += 1
            domainUuidByCode[file.body.code] = domainUuid
        }
        for file in domainFiles {
            let domainUuid = domainUuidByCode[file.body.code]!
            for en in file.enums {
                let enumUuid = try core.insertBase(db, table: "dope_persistence_enum", extra: [
                    "dope_persistence_uuid": domainUuid,
                    "code": en.body.code, "name": en.body.name,
                    "description": en.body.description, "sort_order": en.body.sortOrder,
                    "repo_representative_file": en.body.repoRepresentativeFile,
                ])
                counts.enums += 1
                enumUuidByRef[DopeCode.formatEnumRef(
                    domain: file.body.code, enumCode: en.body.code)] = enumUuid
                for option in en.options {
                    _ = try core.insertBase(db, table: "dope_persistence_enum_option", extra: [
                        "dope_persistence_enum_uuid": enumUuid,
                        "code": option.body.code, "name": option.body.name,
                        "description": option.body.description,
                        "sort_order": option.body.sortOrder,
                    ])
                    counts.options += 1
                }
            }
        }

        // Pass 2 — entities + non-relationship properties (every enum target
        // now exists; a missed enum lookup is a loud error, never a NULL).
        for file in domainFiles {
            let domainUuid = domainUuidByCode[file.body.code]!
            for entity in file.entities {
                let entityUuid = try core.insertBase(db, table: "dope_persistence_entity", extra: [
                    "dope_persistence_uuid": domainUuid,
                    "code": entity.body.code, "name": entity.body.name,
                    "entity_type": entity.body.entityType,
                    "description": entity.body.description,
                    "sort_order": entity.body.sortOrder,
                    "repo_representative_file": entity.body.repoRepresentativeFile,
                ])
                counts.entities += 1
                let entityRef = DopeCode.formatEntityRef(
                    domain: file.body.code, entity: entity.body.code)
                entityUuidByRef[entityRef] = entityUuid
                entityRefByUuid[entityUuid] = entityRef
                if let ref = entity.body.baseComposableRef {
                    pendingBase.append((entityUuid, ref))
                }
                for property in entity.properties {
                    let body = property.body
                    if body.dataType == DopePropertyDataType.relationship.rawValue {
                        pendingRelationship.append((entityUuid, body))
                        continue
                    }
                    var enumUuid: String?
                    if let enumRef = body.enumRef {
                        guard let resolved = enumUuidByRef[enumRef] else {
                            throw StoreError.badRequest(
                                detail: "enum property '\(body.code)' ref '\(enumRef)' did not resolve during insert")
                        }
                        enumUuid = resolved
                    }
                    let uuid = try core.insertBase(db, table: "dope_persistence_entity_property", extra: [
                        "dope_persistence_entity_uuid": entityUuid,
                        "code": body.code, "name": body.name,
                        "description": body.description, "sort_order": body.sortOrder,
                        "data_type": body.dataType,
                        "nullable": body.nullable ? 1 : 0,
                        "is_unique": body.isUnique ? 1 : 0,
                        "auto_increment": body.autoIncrement.map { $0 ? 1 : 0 },
                        "text_char_limit": body.textCharLimit,
                        "dope_persistence_enum_uuid": enumUuid,
                        "relationship_target_uuid": nil,
                    ])
                    counts.properties += 1
                    propertyUuidByRef[DopeCode.formatPropertyRef(
                        domain: file.body.code, entity: entity.body.code,
                        property: body.code)] = uuid
                    if let originRef = body.baseOriginRef {
                        pendingBaseOrigin.append((uuid, originRef))
                    }
                }
            }
        }
        // Pass 3 — base_composable back-fill, after ALL entities exist across
        // ALL files: base refs are cross-domain-capable like enum refs, so an
        // inline resolve would miss a forward ref into a later file. A plain
        // UPDATE, not updateBase — these are fresh rows and the whole-tree
        // counter is dope_scope.revision, so row version stays 0.
        for pending in pendingBase {
            guard let target = entityUuidByRef[pending.ref] else {
                throw StoreError.badRequest(
                    detail: "entity base_composable_ref '\(pending.ref)' did not resolve during insert")
            }
            try db.execute(
                sql: "UPDATE dope_persistence_entity SET base_composable_uuid = ? WHERE uuid = ?",
                arguments: [target, pending.entityUuid])
        }
        // Relationship properties last: the validator bans chain refs, so
        // every target is a non-relationship property inserted above.
        for pending in pendingRelationship {
            let body = pending.body
            guard let ref = body.relationshipTargetRef,
                  let target = propertyUuidByRef[ref] else {
                throw StoreError.badRequest(
                    detail: "relationship property '\(body.code)' target '\(body.relationshipTargetRef ?? "nil")' did not resolve during insert")
            }
            let uuid = try core.insertBase(db, table: "dope_persistence_entity_property", extra: [
                "dope_persistence_entity_uuid": pending.entityUuid,
                "code": body.code, "name": body.name,
                "description": body.description, "sort_order": body.sortOrder,
                "data_type": body.dataType,
                "nullable": body.nullable ? 1 : 0,
                "is_unique": body.isUnique ? 1 : 0,
                "auto_increment": nil,
                "text_char_limit": nil,
                "dope_persistence_enum_uuid": nil,
                "relationship_target_uuid": target,
            ])
            counts.properties += 1
            if let entityRef = entityRefByUuid[pending.entityUuid] {
                propertyUuidByRef["\(entityRef).\(body.code)"] = uuid
            }
            if let originRef = body.baseOriginRef {
                pendingBaseOrigin.append((uuid, originRef))
            }
        }
        // Pass 5 — base_origin back-fill, after EVERY property (including the
        // deferred relationship rows) exists: origins are cross-domain-capable
        // and, unlike relationship targets, may themselves be relationship
        // properties. Same plain-UPDATE reasoning as pass 3.
        for pending in pendingBaseOrigin {
            guard let target = propertyUuidByRef[pending.ref] else {
                throw StoreError.badRequest(
                    detail: "property base_origin_ref '\(pending.ref)' did not resolve during insert")
            }
            try db.execute(sql: """
                UPDATE dope_persistence_entity_property SET base_origin_property_uuid = ? WHERE uuid = ?
                """, arguments: [target, pending.propertyUuid])
        }
        return DopeTreeCounts(domains: counts.domains, entities: counts.entities,
                              properties: counts.properties, enums: counts.enums,
                              options: counts.options)
    }

    /// The ordered whole-tree wipe: relationship properties, then all
    /// remaining properties, then domains (CASCADE clears entities, enums,
    /// options). Never rely on CASCADE to unwind a RESTRICT.
    func wipeDopeTree(scopeUuid: String) throws {
        // Entities compose each other under an ON DELETE RESTRICT self-FK, so
        // un-link every base BEFORE the domain CASCADE reaches the rows — a
        // base pair inside one domain would otherwise trip the RESTRICT
        // mid-statement. Rows about to be deleted; version deliberately
        // untouched.
        try db.execute(sql: """
            UPDATE dope_persistence_entity SET base_composable_uuid = NULL
             WHERE base_composable_uuid IS NOT NULL
               AND dope_persistence_uuid IN (
                SELECT uuid FROM dope_persistence WHERE dope_scope_uuid = ?)
            """, arguments: [scopeUuid])
        // base_origin is data_type-INDEPENDENT, so the relationship-first
        // DELETE split below cannot separate origin referrers from their
        // targets — NULL every tag before either property DELETE runs.
        try db.execute(sql: """
            UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
             WHERE base_origin_property_uuid IS NOT NULL
               AND dope_persistence_entity_uuid IN (
                SELECT e.uuid FROM dope_persistence_entity e
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE d.dope_scope_uuid = ?)
            """, arguments: [scopeUuid])
        try db.execute(sql: """
            DELETE FROM dope_persistence_entity_property
             WHERE data_type = 'relationship'
               AND dope_persistence_entity_uuid IN (
                SELECT e.uuid FROM dope_persistence_entity e
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE d.dope_scope_uuid = ?)
            """, arguments: [scopeUuid])
        try db.execute(sql: """
            DELETE FROM dope_persistence_entity_property
             WHERE dope_persistence_entity_uuid IN (
                SELECT e.uuid FROM dope_persistence_entity e
                  JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                 WHERE d.dope_scope_uuid = ?)
            """, arguments: [scopeUuid])
        try db.execute(
            sql: "DELETE FROM dope_persistence WHERE dope_scope_uuid = ?",
            arguments: [scopeUuid])
        // Cogs go in the SAME wipe: an ingest that replaced persistence but
        // left cogs behind would leave the two areas describing different
        // revisions of the tree.
        try db.execute(
            sql: "DELETE FROM dope_cog WHERE dope_scope_uuid = ?",
            arguments: [scopeUuid])
    }

    /// Insert the cogs area of an ingested bundle, expanding each hull's
    /// collapsed `links.persistence_owners` back into sibling
    /// PersistenceOwner element rows.
    func insertDopeCogs(
        scopeUuid: String, cogFiles: [DopeCogDocument]
    ) throws {
        for (cogIndex, cog) in cogFiles.enumerated() {
            let cogUuid = try core.insertBase(db, table: "dope_cog", extra: [
                "dope_scope_uuid": scopeUuid,
                "code": cog.body.code, "name": cog.body.name,
                "description": cog.body.description,
                "sort_order": cog.body.sortOrder == 0 ? cogIndex : cog.body.sortOrder,
                "content_revision": 0,
            ])
            for element in cog.elements {
                let spec = try DopeCogElementSpec.spec(for: element.elementType)
                let elementUuid = try core.insertBase(db, table: "dope_cog_element", extra: [
                    "dope_cog_uuid": cogUuid,
                    "parent_element_uuid": nil,
                    "element_type": element.elementType,
                    "code": element.code, "name": element.name,
                    "description": element.description,
                    "sort_order": element.sortOrder,
                    "dope_scope_code": element.dopeScopeCode,
                ])
                var subtype: [String: (any DatabaseValueConvertible)?] = ["element_uuid": elementUuid]
                if spec.ownedFields.contains(.primaryPath) {
                    subtype["primary_path"] = element.primaryPath ?? ""
                }
                _ = try core.insertBase(db, table: spec.subtypeTable, extra: subtype)

                // Expand the links block back into child rows, using the ONE
                // synthesis both the reader and the seeder share.
                for (i, owned) in (element.links?.persistenceOwners ?? []).enumerated() {
                    let child = DopeCogProjection.ownerElement(
                        parentCode: element.code, persistenceCode: owned, sortOrder: i)
                    let childUuid = try core.insertBase(db, table: "dope_cog_element", extra: [
                        "dope_cog_uuid": cogUuid,
                        "parent_element_uuid": elementUuid,
                        "element_type": DopeCogElementType.persistenceOwner.rawValue,
                        "code": child.code, "name": child.name,
                        "description": child.description,
                        "sort_order": child.sortOrder,
                        "dope_scope_code": nil,
                    ])
                    _ = try core.insertBase(db, table: "dope_cog_persistence_owner", extra: [
                        "element_uuid": childUuid,
                        "dope_persistence_code": owned,
                    ])
                }
            }
        }
    }

    // MARK: - Generic node mutations

    private func requireOwnedFields(_ fields: DopeNodeFields, level: DopeLevel) throws {
        let spec = DopeLevelSpec.spec(for: level)
        var carried: [DopeField] = []
        if fields.code != nil { carried.append(.code) }
        if fields.name != nil { carried.append(.name) }
        if fields.description != nil { carried.append(.description) }
        if fields.sortOrder != nil { carried.append(.sortOrder) }
        if fields.entityType != nil { carried.append(.entityType) }
        if fields.repoRepresentativeFile != nil || fields.clearRepoRepresentativeFile == true {
            carried.append(.repoRepresentativeFile)
        }
        if fields.baseComposableUuid != nil || fields.clearBaseComposable == true {
            carried.append(.baseComposableUuid)
        }
        if fields.dataType != nil { carried.append(.dataType) }
        if fields.nullable != nil { carried.append(.nullable) }
        if fields.isUnique != nil { carried.append(.isUnique) }
        if fields.autoIncrement != nil || fields.clearAutoIncrement == true {
            carried.append(.autoIncrement)
        }
        if fields.textCharLimit != nil || fields.clearTextCharLimit == true {
            carried.append(.textCharLimit)
        }
        if fields.enumUuid != nil || fields.clearEnum == true { carried.append(.enumUuid) }
        if fields.relationshipTargetUuid != nil || fields.clearRelationshipTarget == true {
            carried.append(.relationshipTargetUuid)
        }
        if fields.baseOriginPropertyUuid != nil || fields.clearBaseOrigin == true {
            carried.append(.baseOriginPropertyUuid)
        }
        for field in carried where !spec.ownedFields.contains(field) {
            throw StoreError.badRequest(
                detail: "level '\(level.rawValue)' has no field '\(field.rawValue)'")
        }
    }

    private func validateDopeDescription(_ text: String?, level: DopeLevel) throws {
        guard let text else { return }
        let limit = Self.dopeDescriptionLimits[level] ?? 128
        guard text.count <= limit else {
            throw StoreError.badRequest(
                detail: "\(level.rawValue) description exceeds \(limit) characters")
        }
    }

    /// Same-scope + shape checks for a property's final (post-mutation)
    /// state. The schema CHECKs are the backstop; this produces the friendly
    /// message and enforces what SQL cannot see (same scope, no chain refs).
    private func validatePropertyShape(
        scope: DopeScopeRow, propertyUuid: String?, entityUuid: String,
        dataType: String, enumUuid: String?, relationshipTargetUuid: String?,
        baseOriginPropertyUuid: String?,
        autoIncrement: Bool?, textCharLimit: Int?
    ) throws {
        guard let type = DopePropertyDataType(rawValue: dataType) else {
            throw StoreError.badRequest(detail: "unknown data_type '\(dataType)'")
        }
        if (type == .enumeration) != (enumUuid != nil) {
            throw StoreError.badRequest(
                detail: "enum properties require --enum-uuid, and only enum properties may carry one")
        }
        if (type == .relationship) != (relationshipTargetUuid != nil) {
            throw StoreError.badRequest(
                detail: "relationship properties require --related-property-uuid, and only relationship properties may carry one")
        }
        if autoIncrement != nil && type != .long {
            throw StoreError.badRequest(detail: "auto_increment is only legal on 'long' properties")
        }
        if textCharLimit != nil && type != .text {
            throw StoreError.badRequest(detail: "text_char_limit is only legal on 'text' properties")
        }
        if let enumUuid {
            let owner = try dopeOwningScope(level: .enumeration, nodeUuid: enumUuid)
            guard owner.uuid == scope.uuid else {
                throw StoreError.badRequest(
                    detail: "enum \(enumUuid) belongs to a different dope scope")
            }
        }
        if let relationshipTargetUuid {
            let owner = try dopeOwningScope(level: .property, nodeUuid: relationshipTargetUuid)
            guard owner.uuid == scope.uuid else {
                throw StoreError.badRequest(
                    detail: "target property \(relationshipTargetUuid) belongs to a different dope scope")
            }
            let targetType = try String.fetchOne(
                db, sql: "SELECT data_type FROM dope_persistence_entity_property WHERE uuid = ?",
                arguments: [relationshipTargetUuid])
            if targetType == DopePropertyDataType.relationship.rawValue {
                throw StoreError.badRequest(
                    detail: "target property \(relationshipTargetUuid) is itself a relationship — chain refs are not allowed")
            }
        }
        if let origin = baseOriginPropertyUuid {
            if origin == propertyUuid {
                throw StoreError.badRequest(detail: "a property cannot originate from itself")
            }
            let owner = try dopeOwningScope(level: .property, nodeUuid: origin)
            guard owner.uuid == scope.uuid else {
                throw StoreError.badRequest(
                    detail: "base origin property \(origin) belongs to a different dope scope")
            }
            // dopeOwningScope proves existence + scope; the origin's
            // data_type, owning entity, and that entity's kind ride in on
            // one join.
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.data_type AS data_type,
                       e.uuid AS entity_uuid,
                       e.entity_type AS entity_type
                  FROM dope_persistence_entity_property p
                  JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                 WHERE p.uuid = ?
                """, arguments: [origin])
            else {
                throw StoreError.corruptState(
                    entity: "dope_persistence_entity_property",
                    detail: "base origin \(origin) vanished")
            }
            let originEntity: String = row["entity_uuid"]
            // Defense-in-depth only: every base_composable target is
            // type-checked on write and the demotion guard holds it, so this
            // fires only on corrupt or hand-edited rows.
            guard (row["entity_type"] as String?) == DopeEntityType.baseComposable.rawValue else {
                throw StoreError.badRequest(detail:
                    "base origin property \(origin) lives on \(originEntity), which is not a BASE_COMPOSABLE")
            }
            try requireBaseChainReaches(entityUuid: entityUuid, targetUuid: originEntity)
            let originType: String = row["data_type"]
            guard originType == dataType else {
                throw StoreError.badRequest(detail:
                    "base origin property \(origin) is '\(originType)', not '\(dataType)' — a materialized property must keep the origin's data_type")
            }
        }
    }

    /// The materialization rule: `entityUuid` must actually compose
    /// `targetUuid`, directly or through the chain. Out-degree is 1, so this
    /// is requireAcyclicBase's pointer-chase walked forwards; the visited set
    /// keeps a pre-existing cycle from hanging the walk.
    private func requireBaseChainReaches(
        entityUuid: String, targetUuid: String
    ) throws {
        var seen: Set<String> = []
        var node: String? = try String.fetchOne(
            db, sql: "SELECT base_composable_uuid FROM dope_persistence_entity WHERE uuid = ?",
            arguments: [entityUuid]) ?? nil
        while let current = node {
            if current == targetUuid { return }
            guard seen.insert(current).inserted else { break }
            node = try String.fetchOne(
                db, sql: "SELECT base_composable_uuid FROM dope_persistence_entity WHERE uuid = ?",
                arguments: [current]) ?? nil
        }
        throw StoreError.badRequest(detail:
            "entity \(entityUuid) does not compose \(targetUuid) — a property may only be materialized from a base its entity composes")
    }

    /// Same-scope + shape checks for an entity's final (post-mutation) state.
    /// `entityUuid` is nil on add (a row nothing can reference yet).
    private func validateEntityShape(
        scope: DopeScopeRow, entityUuid: String?,
        entityType: DopeEntityType, baseComposableUuid: String?
    ) throws {
        if let target = baseComposableUuid {
            if target == entityUuid {
                throw StoreError.badRequest(detail: "an entity cannot compose itself")
            }
            let owner = try dopeOwningScope(level: .entity, nodeUuid: target)
            guard owner.uuid == scope.uuid else {
                throw StoreError.badRequest(
                    detail: "base entity \(target) belongs to a different dope scope")
            }
            // dopeOwningScope proves existence + scope; the TYPE needs its
            // own read.
            let targetType = try String.fetchOne(
                db, sql: "SELECT entity_type FROM dope_persistence_entity WHERE uuid = ?",
                arguments: [target])
            guard targetType == DopeEntityType.baseComposable.rawValue else {
                throw StoreError.badRequest(detail:
                    "base entity \(target) is \(targetType ?? "unknown") — only a BASE_COMPOSABLE may be composed")
            }
            if let entityUuid {
                try requireAcyclicBase(entityUuid: entityUuid, targetUuid: target)
            }
        }
        // Demotion guard: an entity that others compose may not stop being a
        // BASE_COMPOSABLE. A cross-row rule the schema cannot express, so it
        // lives here and in the whole-tree validator.
        if entityType != .baseComposable, let entityUuid {
            let referrers = try baseComposableReferrers(entityUuid: entityUuid)
            guard referrers.isEmpty else {
                throw StoreError.badRequest(detail:
                    "cannot set entity_type \(entityType.rawValue): still composed by "
                    + referrers.joined(separator: ", "))
            }
        }
        // Strand guard: this entity's materialized properties tag origins on
        // base entities the FINAL chain must still reach. Receives the final
        // (not requested) base — passing the requested value would
        // false-refuse ordinary updates. Fires on ANY base change that
        // strands a tag (clear OR re-point); no-op on add (no properties
        // yet) and self-neutralizing when the base is unchanged.
        if let entityUuid {
            let tagged = try Row.fetchAll(db, sql: """
                SELECT p.code AS code, oe.uuid AS origin_entity
                  FROM dope_persistence_entity_property p
                  JOIN dope_persistence_entity_property op ON op.uuid = p.base_origin_property_uuid
                  JOIN dope_persistence_entity oe ON oe.uuid = op.dope_persistence_entity_uuid
                 WHERE p.dope_persistence_entity_uuid = ?
                   AND p.base_origin_property_uuid IS NOT NULL
                """, arguments: [entityUuid])
            if !tagged.isEmpty {
                var reachable = Set<String>()
                var node = baseComposableUuid
                while let current = node, reachable.insert(current).inserted {
                    node = try String.fetchOne(
                        db, sql: "SELECT base_composable_uuid FROM dope_persistence_entity WHERE uuid = ?",
                        arguments: [current]) ?? nil
                }
                let stranded = tagged.filter { !reachable.contains($0["origin_entity"] as String) }
                    .map { $0["code"] as String }
                guard stranded.isEmpty else {
                    throw StoreError.badRequest(detail:
                        "cannot change base_composable: property "
                        + stranded.joined(separator: ", ")
                        + " still originates from a base this entity would no longer compose")
                }
            }
        }
    }

    /// Chaining is ALLOWED but must stay acyclic. Out-degree is 1 (a single
    /// nullable column), so "does the chain from target reach entity?" is a
    /// bounded pointer-chase, not a graph search. The visited set is
    /// defensive only — a pre-existing cycle cannot be reached through these
    /// guards.
    private func requireAcyclicBase(
        entityUuid: String, targetUuid: String
    ) throws {
        var seen: Set<String> = [entityUuid]
        var node: String? = targetUuid
        while let current = node {
            guard seen.insert(current).inserted else {
                if current == entityUuid {
                    throw StoreError.badRequest(detail:
                        "base_composable cycle: \(entityUuid) already sits on \(targetUuid)'s base chain")
                }
                return  // corruption below us; not this mutation's cycle
            }
            node = try String.fetchOne(
                db, sql: "SELECT base_composable_uuid FROM dope_persistence_entity WHERE uuid = ?",
                arguments: [current]) ?? nil
        }
    }

    /// Dot-paths of the entities composing `entityUuid` (bounded at 5, the
    /// requireNoExternalReferrers convention).
    private func baseComposableReferrers(
        entityUuid: String
    ) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT d.code || '.' || e.code
            FROM dope_persistence_entity e
            JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
            WHERE e.base_composable_uuid = ? LIMIT 5
            """, arguments: [entityUuid])
    }

    func dopeNodeAdd(_ req: DopeNodeAddRequest) throws -> DopeNodeResponse {
        guard req.level != .scope else {
            throw StoreError.badRequest(detail: "scopes are created with DOPE_INIT, not node-add")
        }
        let spec = DopeLevelSpec.spec(for: req.level)
        try requireOwnedFields(req.fields, level: req.level)
        guard let code = req.fields.code, let name = req.fields.name else {
            throw StoreError.badRequest(detail: "node-add requires --code and --name")
        }
        try DopeCode.validateCode(code, field: "\(req.level.rawValue) code")
        if req.level == .entity, code == DopeCode.reservedEnumSegment {
            throw StoreError.badRequest(
                detail: "'enums' is a reserved entity code (it disambiguates enum refs)")
        }
        try validateDopeDescription(req.fields.description, level: req.level)

        guard let parentLevel = spec.parentLevel, let parentColumn = spec.parentColumn else {
            throw StoreError.corruptState(entity: spec.table, detail: "level has no parent")
        }
        let scope = try dopeOwningScope(level: parentLevel, nodeUuid: req.parentUuid)

        var extra: [String: (any DatabaseValueConvertible)?] = [
            parentColumn: req.parentUuid,
            "code": code,
            "name": name,
            "description": req.fields.description ?? "",
        ]
        let sortOrder: Int
        if let requested = req.fields.sortOrder {
            sortOrder = requested
        } else {
            sortOrder = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sort_order), -1) + 1 FROM \(spec.table)
                WHERE \(parentColumn) = ?
                """, arguments: [req.parentUuid]) ?? 0
        }
        extra["sort_order"] = sortOrder

        switch req.level {
        case .entity:
            let entityType = req.fields.entityType ?? .model
            try validateEntityShape(
                scope: scope, entityUuid: nil, entityType: entityType,
                baseComposableUuid: req.fields.baseComposableUuid)
            extra["entity_type"] = entityType.rawValue
            extra["repo_representative_file"] = req.fields.repoRepresentativeFile
            extra["base_composable_uuid"] = req.fields.baseComposableUuid
        case .enumeration:
            extra["repo_representative_file"] = req.fields.repoRepresentativeFile
        case .property:
            guard let dataType = req.fields.dataType else {
                throw StoreError.badRequest(detail: "property-add requires --data-type")
            }
            try validatePropertyShape(
                scope: scope, propertyUuid: nil, entityUuid: req.parentUuid,
                dataType: dataType.rawValue,
                enumUuid: req.fields.enumUuid,
                relationshipTargetUuid: req.fields.relationshipTargetUuid,
                baseOriginPropertyUuid: req.fields.baseOriginPropertyUuid,
                autoIncrement: req.fields.autoIncrement,
                textCharLimit: req.fields.textCharLimit)
            extra["data_type"] = dataType.rawValue
            extra["nullable"] = (req.fields.nullable ?? true) ? 1 : 0
            extra["is_unique"] = (req.fields.isUnique ?? false) ? 1 : 0
            extra["auto_increment"] = req.fields.autoIncrement.map { $0 ? 1 : 0 }
            extra["text_char_limit"] = req.fields.textCharLimit
            extra["dope_persistence_enum_uuid"] = req.fields.enumUuid
            extra["relationship_target_uuid"] = req.fields.relationshipTargetUuid
            extra["base_origin_property_uuid"] = req.fields.baseOriginPropertyUuid
        default:
            break
        }

        let uuid = try core.insertBase(db, table: spec.table, extra: extra)
        let revision = try bumpScopeRevision(
            scopeUuid: scope.uuid, area: .persistence,
            ownerUuid: try owningPersistenceUuid(level: req.level, nodeUuid: uuid))
        try recordDopeChange(scope: scope, action: "node_add", level: req.level,
                                  nodeUuid: uuid, revision: revision)
        return DopeNodeResponse(level: req.level, uuid: uuid, version: 0,
                                scopeUuid: scope.uuid, revision: revision)
    }

    func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        let spec = DopeLevelSpec.spec(for: req.level)
        try requireOwnedFields(req.fields, level: req.level)
        if let code = req.fields.code {
            try DopeCode.validateCode(code, field: "\(req.level.rawValue) code")
            if req.level == .entity, code == DopeCode.reservedEnumSegment {
                throw StoreError.badRequest(
                    detail: "'enums' is a reserved entity code (it disambiguates enum refs)")
            }
        }
        try validateDopeDescription(req.fields.description, level: req.level)

        let scope = try dopeOwningScope(level: req.level, nodeUuid: req.nodeUuid)

        var set: [String: (any DatabaseValueConvertible)?] = [:]
        if let code = req.fields.code { set["code"] = code }
        if let name = req.fields.name { set["name"] = name }
        if let description = req.fields.description { set["description"] = description }
        if let sortOrder = req.fields.sortOrder { set["sort_order"] = sortOrder }
        if req.level == .entity, let entityType = req.fields.entityType {
            set["entity_type"] = entityType.rawValue
        }
        if req.level == .entity || req.level == .enumeration {
            if let file = req.fields.repoRepresentativeFile {
                set["repo_representative_file"] = file
            } else if req.fields.clearRepoRepresentativeFile == true {
                // updateValue, not subscript: a nil subscript assignment
                // REMOVES the key and the clear vanishes from the UPDATE.
                set.updateValue(nil, forKey: "repo_representative_file")
            }
        }

        if req.level == .entity {
            guard let current = try Row.fetchOne(
                db, sql: "SELECT * FROM dope_persistence_entity WHERE uuid = ?",
                arguments: [req.nodeUuid]
            ) else {
                throw StoreError.notFound(entity: spec.table, key: req.nodeUuid)
            }
            // Validate the FINAL (entity_type, base_composable) pair —
            // either half can change in one call, and the second call of
            // A.base=B / B.base=A must be the one that gets refused.
            let finalType = req.fields.entityType
                ?? DopeEntityType(rawValue: current["entity_type"]) ?? .model
            var finalBase: String? = current["base_composable_uuid"]
            if let base = req.fields.baseComposableUuid { finalBase = base }
            if req.fields.clearBaseComposable == true { finalBase = nil }

            try validateEntityShape(
                scope: scope, entityUuid: req.nodeUuid,
                entityType: finalType, baseComposableUuid: finalBase)

            if req.fields.baseComposableUuid != nil || req.fields.clearBaseComposable == true {
                // updateValue, not subscript: assigning a typed nil to a
                // dictionary with Optional values REMOVES the key, and the
                // clear would silently vanish from the UPDATE.
                set.updateValue(finalBase, forKey: "base_composable_uuid")
            }
        }

        if req.level == .property {
            guard let current = try Row.fetchOne(
                db, sql: "SELECT * FROM dope_persistence_entity_property WHERE uuid = ?",
                arguments: [req.nodeUuid]
            ) else {
                throw StoreError.notFound(entity: spec.table, key: req.nodeUuid)
            }
            let finalDataType: String = req.fields.dataType?.rawValue
                ?? (current["data_type"] as String)
            var finalEnum: String? = current["dope_persistence_enum_uuid"]
            if let enumUuid = req.fields.enumUuid { finalEnum = enumUuid }
            if req.fields.clearEnum == true { finalEnum = nil }
            var finalRelated: String? = current["relationship_target_uuid"]
            if let related = req.fields.relationshipTargetUuid { finalRelated = related }
            if req.fields.clearRelationshipTarget == true { finalRelated = nil }
            var finalAutoIncrement = (current["auto_increment"] as Int64?).map { $0 != 0 }
            if let autoIncrement = req.fields.autoIncrement { finalAutoIncrement = autoIncrement }
            if req.fields.clearAutoIncrement == true { finalAutoIncrement = nil }
            var finalCharLimit: Int? = current["text_char_limit"]
            if let limit = req.fields.textCharLimit { finalCharLimit = limit }
            if req.fields.clearTextCharLimit == true { finalCharLimit = nil }
            var finalBaseOrigin: String? = current["base_origin_property_uuid"]
            if let origin = req.fields.baseOriginPropertyUuid { finalBaseOrigin = origin }
            if req.fields.clearBaseOrigin == true { finalBaseOrigin = nil }

            try validatePropertyShape(
                scope: scope, propertyUuid: req.nodeUuid,
                entityUuid: current["dope_persistence_entity_uuid"],
                dataType: finalDataType,
                enumUuid: finalEnum, relationshipTargetUuid: finalRelated,
                baseOriginPropertyUuid: finalBaseOrigin,
                autoIncrement: finalAutoIncrement, textCharLimit: finalCharLimit)

            if let dataType = req.fields.dataType { set["data_type"] = dataType.rawValue }
            if let nullable = req.fields.nullable { set["nullable"] = nullable ? 1 : 0 }
            if let isUnique = req.fields.isUnique { set["is_unique"] = isUnique ? 1 : 0 }
            // updateValue throughout, not subscript: a typed-nil subscript
            // assignment REMOVES the key, so a clear-alone call would
            // throw emptyUpdate and a combined call would silently skip
            // the clear (the base_composable_uuid trap, all five sites).
            if req.fields.autoIncrement != nil || req.fields.clearAutoIncrement == true {
                set.updateValue(finalAutoIncrement.map { $0 ? 1 : 0 },
                                forKey: "auto_increment")
            }
            if req.fields.textCharLimit != nil || req.fields.clearTextCharLimit == true {
                set.updateValue(finalCharLimit, forKey: "text_char_limit")
            }
            if req.fields.enumUuid != nil || req.fields.clearEnum == true {
                set.updateValue(finalEnum, forKey: "dope_persistence_enum_uuid")
            }
            if req.fields.relationshipTargetUuid != nil || req.fields.clearRelationshipTarget == true {
                set.updateValue(finalRelated, forKey: "relationship_target_uuid")
            }
            if req.fields.baseOriginPropertyUuid != nil || req.fields.clearBaseOrigin == true {
                // updateValue, not subscript — the typed-nil clear trap
                // (same shape as base_composable_uuid above).
                set.updateValue(finalBaseOrigin, forKey: "base_origin_property_uuid")
            }
        }

        guard !set.isEmpty else {
            throw StoreError.emptyUpdate(entity: spec.table)
        }
        try core.updateBase(db, table: spec.table, uuid: req.nodeUuid,
                            expectedVersion: req.expectedVersion, set: set)
        let revision = try bumpScopeRevision(
            scopeUuid: scope.uuid, area: .persistence,
            ownerUuid: try owningPersistenceUuid(
                level: req.level, nodeUuid: req.nodeUuid))
        try recordDopeChange(scope: scope, action: "node_update", level: req.level,
                                  nodeUuid: req.nodeUuid, revision: revision)
        guard let version = try Int64.fetchOne(
            db, sql: "SELECT version FROM \(spec.table) WHERE uuid = ?",
            arguments: [req.nodeUuid]
        ) else {
            throw StoreError.corruptState(entity: spec.table, detail: "vanished after update")
        }
        return DopeNodeResponse(level: req.level, uuid: req.nodeUuid, version: version,
                                scopeUuid: scope.uuid, revision: revision)
    }

    func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        guard req.level != .scope else {
            throw StoreError.badRequest(
                detail: "scope deletion is deferred to a later pass (it destroys the whole tree)")
        }
        let spec = DopeLevelSpec.spec(for: req.level)
        let scope = try dopeOwningScope(level: req.level, nodeUuid: req.nodeUuid)

        // Soft delete is a stamp, not a removal. It deliberately skips
        // BOTH the referrer guard and the cascade: a tombstoned row is
        // still a row, so every RESTRICT FK pointing at it still resolves
        // and nothing below it needs to go. Reads do not filter it — that
        // is the point.
        if req.soft == true {
            // A tombstone is a MASKING artifact, not real state. It is
            // assumed absent from a base scope and rides only on the
            // overlay tiers, which are db-only and never serialized --
            // which is exactly why deleted_on lives on the wire identity
            // layer and never in a .doped.json. Soft-deleting inside a
            // base scope would put a value in the saved format that does
            // not describe anything real, so it is refused outright.
            guard scope.tier?.isOverlay == true else {
                throw StoreError.badRequest(
                    detail: "--soft is only valid inside a masking scope "
                          + "(PROJECT_ITEM / SESSION_INSTANCE_ITEM); scope "
                          + "\(scope.uuid) is \(scope.scopeType). A base scope "
                          + "records real state only -- use a hard delete.")
            }
            guard try Row.fetchOne(
                db, sql: "SELECT deleted_on FROM \(spec.table) WHERE uuid = ?",
                arguments: [req.nodeUuid]
            )?["deleted_on"] as String? == nil else {
                throw StoreError.badRequest(
                    detail: "node \(req.nodeUuid) is already soft-deleted")
            }
            try core.updateBase(
                db, table: spec.table, uuid: req.nodeUuid,
                expectedVersion: req.expectedVersion,
                set: ["deleted_on": Store.isoNow()])
            let revision = try bumpScopeRevision(
                scopeUuid: scope.uuid, area: .persistence,
                ownerUuid: try owningPersistenceUuid(
                    level: req.level, nodeUuid: req.nodeUuid))
            try recordDopeChange(
                scope: scope, action: "node_soft_delete", level: req.level,
                nodeUuid: req.nodeUuid, revision: revision)
            return DopeNodeDeleteResponse(
                deletedUuid: req.nodeUuid,
                cascaded: DopeTreeCounts(domains: 0, entities: 0, properties: 0,
                                         enums: 0, options: 0),
                scopeUuid: scope.uuid, revision: revision)
        }

        try requireNoExternalReferrers(level: req.level, nodeUuid: req.nodeUuid)
        let cascaded = try dopeCascadeCounts(level: req.level, nodeUuid: req.nodeUuid)

        // Ordered deletes so a CASCADE can never race a RESTRICT: a
        // node's own relationship properties (referrers) go first, then
        // the remaining properties under it, then the guarded row.
        switch req.level {
        case .persistence:
            // Entities inside this domain may compose one another under
            // an ON DELETE RESTRICT self-FK; the CASCADE below would trip
            // it. External composers were already refused by the guard.
            try db.execute(sql: """
                UPDATE dope_persistence_entity SET base_composable_uuid = NULL
                 WHERE dope_persistence_uuid = ? AND base_composable_uuid IS NOT NULL
                """, arguments: [req.nodeUuid])
            // Origin tags are data_type-independent — NULL them before
            // BOTH property DELETEs, or a tagged origin that is itself a
            // relationship property trips the RESTRICT mid-statement.
            try db.execute(sql: """
                UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
                 WHERE base_origin_property_uuid IS NOT NULL
                   AND dope_persistence_entity_uuid IN (
                    SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                """, arguments: [req.nodeUuid])
            try db.execute(sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE data_type = 'relationship'
                   AND dope_persistence_entity_uuid IN (
                    SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                """, arguments: [req.nodeUuid])
            try db.execute(sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE dope_persistence_entity_uuid IN (
                    SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                """, arguments: [req.nodeUuid])
        case .entity:
            // Same relationship-first split as the domain case: a bulk
            // delete can scan a same-entity relationship TARGET before
            // its referencer and trip the RESTRICT FK mid-statement.
            try db.execute(sql: """
                UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
                 WHERE base_origin_property_uuid IS NOT NULL
                   AND dope_persistence_entity_uuid = ?
                """, arguments: [req.nodeUuid])
            try db.execute(sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE data_type = 'relationship'
                   AND dope_persistence_entity_uuid = ?
                """, arguments: [req.nodeUuid])
            try db.execute(sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE dope_persistence_entity_uuid = ?
                """, arguments: [req.nodeUuid])
        default:
            break
        }
        try core.deleteBase(db, table: spec.table, uuid: req.nodeUuid,
                            expectedVersion: req.expectedVersion)
        let revision = try bumpScopeRevision(scopeUuid: scope.uuid)
        try recordDopeChange(scope: scope, action: "node_delete", level: req.level,
                                  nodeUuid: req.nodeUuid, revision: revision)
        return DopeNodeDeleteResponse(deletedUuid: req.nodeUuid, cascaded: cascaded,
                                      scopeUuid: scope.uuid, revision: revision)
    }

    /// RESTRICT-friendly pre-checks: name the referring dot-paths instead of
    /// surfacing an opaque FK error. "External" means outside the subtree
    /// being deleted — internal referrers are handled by the ordered deletes.
    private func requireNoExternalReferrers(
        level: DopeLevel, nodeUuid: String
    ) throws {
        // A list, not one statement: the base-composable referrer queries
        // select FROM dope_persistence_entity while the property-ref queries
        // select FROM dope_persistence_entity_property, so they cannot share an
        // OR clause.
        var queries: [(sql: String, args: StatementArguments)] = []
        switch level {
        case .enumeration:
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE p.dope_persistence_enum_uuid = ? LIMIT 5
                """, [nodeUuid]))
        case .property:
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE p.relationship_target_uuid = ? LIMIT 5
                """, [nodeUuid]))
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE p.base_origin_property_uuid = ? LIMIT 5
                """, [nodeUuid]))
        case .entity:
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_persistence_entity_property tp ON tp.uuid = p.relationship_target_uuid
                WHERE tp.dope_persistence_entity_uuid = ?
                  AND p.dope_persistence_entity_uuid != ? LIMIT 5
                """, [nodeUuid, nodeUuid]))
            queries.append(("""
                SELECT d.code || '.' || e.code
                FROM dope_persistence_entity e
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE e.base_composable_uuid = ? LIMIT 5
                """, [nodeUuid]))
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                JOIN dope_persistence_entity_property op ON op.uuid = p.base_origin_property_uuid
                WHERE op.dope_persistence_entity_uuid = ?
                  AND p.dope_persistence_entity_uuid != ? LIMIT 5
                """, [nodeUuid, nodeUuid]))
        case .persistence:
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE d.uuid != ?
                  AND (p.dope_persistence_enum_uuid IN
                        (SELECT uuid FROM dope_persistence_enum WHERE dope_persistence_uuid = ?)
                    OR p.relationship_target_uuid IN
                        (SELECT pp.uuid FROM dope_persistence_entity_property pp
                          JOIN dope_persistence_entity ee ON ee.uuid = pp.dope_persistence_entity_uuid
                         WHERE ee.dope_persistence_uuid = ?))
                LIMIT 5
                """, [nodeUuid, nodeUuid, nodeUuid]))
            queries.append(("""
                SELECT d.code || '.' || e.code
                FROM dope_persistence_entity e
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE d.uuid != ?
                  AND e.base_composable_uuid IN
                      (SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                LIMIT 5
                """, [nodeUuid, nodeUuid]))
            queries.append(("""
                SELECT d.code || '.' || e.code || '.' || p.code
                FROM dope_persistence_entity_property p
                JOIN dope_persistence_entity e ON e.uuid = p.dope_persistence_entity_uuid
                JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                WHERE d.uuid != ?
                  AND p.base_origin_property_uuid IN
                      (SELECT pp.uuid FROM dope_persistence_entity_property pp
                        JOIN dope_persistence_entity ee ON ee.uuid = pp.dope_persistence_entity_uuid
                       WHERE ee.dope_persistence_uuid = ?)
                LIMIT 5
                """, [nodeUuid, nodeUuid]))
        case .scope, .option:
            return
        }
        let referrers = try queries.flatMap {
            try String.fetchAll(db, sql: $0.sql, arguments: $0.args)
        }
        guard referrers.isEmpty else {
            throw StoreError.badRequest(detail:
                "cannot delete: still referenced by " + referrers.joined(separator: ", "))
        }
    }

    private func dopeCascadeCounts(
        level: DopeLevel, nodeUuid: String
    ) throws -> DopeTreeCounts {
        func count(_ sql: String, _ args: StatementArguments = StatementArguments()) throws -> Int {
            try Int.fetchOne(db, sql: sql, arguments: args) ?? 0
        }
        switch level {
        case .persistence:
            let entities = try count(
                "SELECT COUNT(*) FROM dope_persistence_entity WHERE dope_persistence_uuid = ?", [nodeUuid])
            let enums = try count(
                "SELECT COUNT(*) FROM dope_persistence_enum WHERE dope_persistence_uuid = ?", [nodeUuid])
            let options = try count("""
                SELECT COUNT(*) FROM dope_persistence_enum_option WHERE dope_persistence_enum_uuid IN
                    (SELECT uuid FROM dope_persistence_enum WHERE dope_persistence_uuid = ?)
                """, [nodeUuid])
            let properties = try count("""
                SELECT COUNT(*) FROM dope_persistence_entity_property WHERE dope_persistence_entity_uuid IN
                    (SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                """, [nodeUuid])
            return DopeTreeCounts(domains: 1, entities: entities, properties: properties,
                                  enums: enums, options: options)
        case .entity:
            let properties = try count(
                "SELECT COUNT(*) FROM dope_persistence_entity_property WHERE dope_persistence_entity_uuid = ?",
                [nodeUuid])
            return DopeTreeCounts(domains: 0, entities: 1, properties: properties,
                                  enums: 0, options: 0)
        case .enumeration:
            let options = try count(
                "SELECT COUNT(*) FROM dope_persistence_enum_option WHERE dope_persistence_enum_uuid = ?",
                [nodeUuid])
            return DopeTreeCounts(domains: 0, entities: 0, properties: 0,
                                  enums: 1, options: options)
        case .property:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 1, enums: 0, options: 0)
        case .option:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 0, enums: 0, options: 1)
        case .scope:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 0, enums: 0, options: 0)
        }
    }
}
