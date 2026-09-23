import Foundation
import GRDB

/// DOPE domain modeling data access — scope lifecycle, tree hydration, and the
/// generic per-level node mutations.
///
/// Whole-tree repo verbs in Store+DopeRepo. Runs INSIDE a Store transaction;
/// no dbQueue. Two counters split: every `version` is optimistic lock, while
/// `dope_scope.revision` is the whole-tree content counter advanced by
/// `bumpScopeRevision` without touching scope row's version, so a deep property
/// edit cannot invalidate a version a scope editor is holding.
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

    /// Fetches the scope row by uuid.
    /// - Parameter uuid: The scope uuid.
    /// - Returns: The scope row, or nil if not found.
    /// - Throws: Store errors if the fetch fails.
    func fetchDopeScope(uuid: String) throws -> DopeScopeRow? {
        try DopeScopeRecord.all().withUuid(uuid).fetchOne(db).map { $0.dto() }
    }

    /// Advances the whole-tree content counter without bumping the scope row's version.
    ///
    /// When `area` and `ownerUuid` are provided, also advances that subtree's own
    /// counter, enabling clients to compare one area's number instead of refetching the
    /// whole tree. The scope's `revision` remains the sole CAS gate for read-repo and
    /// write-repo, while area counters sit beside it and never replace it. See
    /// StoreCore.touchSession for the versioning strategy.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope uuid.
    ///   - area: The area to advance, if any.
    ///   - ownerUuid: The row uuid that owns this area, required when `area` is provided.
    /// - Returns: The new revision number.
    /// - Throws: Store errors if the update fails.
    @discardableResult
    func bumpScopeRevision(
        scopeUuid: String,
        area: DopeArea? = nil,
        ownerUuid: String? = nil
    ) throws -> Int64 {
        if let area, let ownerUuid {
            try db.execute(
                sql: """
                    UPDATE \(area.table) SET content_revision = content_revision + 1, updated_at = ?
                     WHERE uuid = ?
                    """,
                arguments: [Store.isoNow(), ownerUuid]
            )
        }
        try db.execute(
            sql: "UPDATE dope_scope SET revision = revision + 1, updated_at = ? WHERE uuid = ?",
            arguments: [Store.isoNow(), scopeUuid]
        )
        guard let revision = try scopeRevision(scopeUuid: scopeUuid) else {
            throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
        }
        return revision
    }

    /// Fetches the current revision number for the scope.
    /// - Parameter scopeUuid: The scope uuid.
    /// - Returns: The revision, or nil if not found.
    /// - Throws: Store errors if the fetch fails.
    private func scopeRevision(scopeUuid: String) throws -> Int64? {
        try DopeScopeRecord
            .all()
            .withUuid(scopeUuid)
            .select(DopeScopeRecord.Columns.revision, as: Int64.self)
            .fetchOne(db)
    }

    /// Fetches the instance root path for the session.
    ///
    /// Session-keyed twin of the promptUuid variant in Store+Architecture. Dope's repo
    /// verbs are scope-addressed and scopes hang off sessions.
    ///
    /// - Parameter sessionUuid: The session uuid.
    /// - Returns: The absolute file system path.
    /// - Throws: Store errors if the fetch fails.
    func instanceRoot(sessionUuid: String) throws -> String {
        try InstanceRecord
            .joining(required: InstanceRecord.sessions.withUuid(sessionUuid))
            .select(InstanceRecord.Columns.absoluteFileSystemPath, as: String.self)
            .fetchOne(db) ?? ""
    }

    /// Fetches the scope that owns a node at the given level.
    ///
    /// Resolves ownership by walking the registry's parent links as associations, returning
    /// the scope that contains the node at the specified level.
    ///
    /// - Parameters:
    ///   - level: The level of the node.
    ///   - nodeUuid: The node uuid.
    /// - Returns: The owning scope.
    /// - Throws: `StoreError.notFound` if the node or scope not found; other store errors.
    func dopeOwningScope(level: DopeLevel, nodeUuid: String) throws -> DopeScopeRow {
        let request: QueryInterfaceRequest<DopeScopeRecord>
        switch level {
        case .scope:
            request = DopeScopeRecord.all().withUuid(nodeUuid)
        case .persistence:
            request = DopeScopeRecord.joining(
                required: Self.persistences.withUuid(nodeUuid)
            )
        case .entity:
            request = DopeScopeRecord.joining(
                required: Self.persistences.joining(
                    required: DopePersistenceRecord.entities.unordered().withUuid(nodeUuid)
                )
            )
        case .property:
            request = DopeScopeRecord.joining(
                required: Self.persistences.joining(
                    required: DopePersistenceRecord.entities.unordered()
                        .joining(
                            required: DopePersistenceEntityRecord.properties.unordered()
                                .withUuid(nodeUuid)
                        )
                )
            )
        case .enumeration:
            request = DopeScopeRecord.joining(
                required: Self.persistences.joining(
                    required: DopePersistenceRecord.enums.unordered().withUuid(nodeUuid)
                )
            )
        case .option:
            request = DopeScopeRecord.joining(
                required: Self.persistences.joining(
                    required: DopePersistenceRecord.enums.unordered()
                        .joining(
                            required: DopePersistenceEnumRecord.options.unordered()
                                .withUuid(nodeUuid)
                        )
                )
            )
        }
        guard let row = try request.fetchOne(db) else {
            throw StoreError.notFound(
                entity: DopeLevelSpec.spec(for: level).table,
                key: nodeUuid
            )
        }
        return row.dto()
    }

    /// The scope → persistence hop every owner walk starts from, unordered
    /// because it is a filter here and never a result set.
    private static let persistences = DopeScopeRecord.persistences.unordered()

    /// Records a change event for a dope node.
    ///
    /// Every granular mutation funnels through here, making this the one place the merge base
    /// learns that this session touched an element. Changes are addressed by dot-path so ingest can
    /// re-mint uuids. The session's activity is touched only if the scope has a session.
    ///
    /// - Parameters:
    ///   - scope: The scope that owns the node.
    ///   - action: The mutation action (e.g., "init", "update", "delete").
    ///   - level: The level of the node, or nil for a scope-level change.
    ///   - nodeUuid: The node uuid, or nil for a scope-level change.
    ///   - revision: The current scope revision after the change.
    /// - Throws: Store errors if the event append fails.
    func recordDopeChange(
        scope: DopeScopeRow,
        action: String,
        level: DopeLevel?,
        nodeUuid: String?,
        revision: Int64
    ) throws {
        // Every granular mutation funnels through here, which makes it the
        // one place the merge base learns that this session touched an
        // element. Addressed by dot-path, because ingest re-mints uuids.
        if let level, let nodeUuid, level != .scope {
            if let dotPath = try dopeProvenance.dotPath(nodeUuid: nodeUuid, level: level) {
                try dopeProvenance.markLocallyModified(
                    scopeUuid: scope.uuid,
                    dotPath: dotPath,
                    kind: level.rawValue
                )
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
        try core.appendEvent(
            db,
            kind: .dopeChange,
            subjectUuid: scope.uuid,
            payload: Store.jsonPayload(payload)
        )
        if let sessionUuid = scope.sessionUuid {
            try core.touchSession(db, uuid: sessionUuid)
        }
    }

    // MARK: - Read-time staleness (shared by agent_briefing and care_package)

    /// Reports read-time drift for a stamped scope revision.
    ///
    /// Compares a stamped scope revision against the live one, re-resolving every dot-path
    /// to detect removals. The `drifted` flag guards both sides—missing numbers on either side
    /// are not drift evidence, so never-stamped ref sets report false. This computed result is
    /// never stored.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope uuid, or nil for no drift check.
    ///   - stampedRevision: The revision number from a prior read, or nil.
    ///   - dotPaths: The dot-paths to check for existence.
    /// - Returns: A tuple with the stamped and current revisions, drift flag, and ghost paths.
    /// - Throws: Store errors if the staleness check fails.
    func scopeStaleness(
        scopeUuid: String?,
        stampedRevision: Int64?,
        dotPaths: [String]
    ) throws -> (stamped: Int64?, current: Int64?, drifted: Bool, ghosts: [String]) {
        // No scope -> no drift, no ghosts.
        guard let scopeUuid else { return (stampedRevision, nil, false, []) }
        let current = try scopeRevision(scopeUuid: scopeUuid)
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

    /// Checks whether a dot-path refers to an existing node.
    ///
    /// Forms accepted: `domain`, `domain.entity`, `domain.entity.property`, `domain.enums.enum_code`,
    /// and `domain.enums.enum_code.option_code`. Unparseable paths are treated as missing, never as
    /// errors. Moved verbatim from BriefingRepository; see RepositoryContext doc comment for table naming.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope uuid.
    ///   - path: The dot-path to check.
    /// - Returns: True if the path exists; false if not found or malformed.
    /// - Throws: Store errors if the query fails.
    func dotPathExists(scopeUuid: String, path: String) throws -> Bool {
        let segs = path.split(separator: ".").map(String.init)
        guard !segs.isEmpty, segs.count <= 4 else { return false }
        guard
            let persistenceUuid =
                try DopePersistenceRecord
                .filter(DopePersistenceRecord.Columns.dopeScopeUuid == scopeUuid)
                .filter(DopePersistenceRecord.Columns.code == segs[0])
                .select(DopePersistenceRecord.Columns.uuid, as: String.self)
                .fetchOne(db)
        else { return false }
        if segs.count == 1 { return true }

        if segs[1] == DopeCode.reservedEnumSegment {
            guard segs.count >= 3 else { return false }
            guard
                let enumUuid =
                    try DopePersistenceEnumRecord
                    .filter(
                        DopePersistenceEnumRecord.Columns.dopePersistenceUuid == persistenceUuid
                    )
                    .filter(DopePersistenceEnumRecord.Columns.code == segs[2])
                    .select(DopePersistenceEnumRecord.Columns.uuid, as: String.self)
                    .fetchOne(db)
            else { return false }
            if segs.count == 3 { return true }
            return try DopePersistenceEnumOptionRecord
                .filter(DopePersistenceEnumOptionRecord.Columns.dopePersistenceEnumUuid == enumUuid)
                .filter(DopePersistenceEnumOptionRecord.Columns.code == segs[3])
                .fetchCount(db) > 0
        }

        guard
            let entityUuid =
                try DopePersistenceEntityRecord
                .filter(
                    DopePersistenceEntityRecord.Columns.dopePersistenceUuid == persistenceUuid
                )
                .filter(DopePersistenceEntityRecord.Columns.code == segs[1])
                .select(DopePersistenceEntityRecord.Columns.uuid, as: String.self)
                .fetchOne(db)
        else { return false }
        if segs.count == 2 { return true }
        guard segs.count == 3 else { return false }
        return try DopePersistenceEntityPropertyRecord
            .filter(
                DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEntityUuid == entityUuid
            )
            .filter(DopePersistenceEntityPropertyRecord.Columns.code == segs[2])
            .fetchCount(db) > 0
    }

    // MARK: - Init

    /// Initializes a new dope scope for a session or prompt.
    /// - Parameter req: The initialization request with session, prompt, code, and description.
    /// - Returns: A response with the created scope and created flag.
    /// - Throws: Validation errors if code is invalid, description too long, or session/prompt not found.
    func dopeInit(_ req: DopeInitRequest) throws -> DopeScopeResponse {
        let description = try validateDopeInit(req)

        let scopeType: DopeScopeType = req.promptUuid == nil ? .sessionInstance : .sessionInstanceItem
        if let row = try existingDopeScope(req, scopeType: scopeType) {
            return DopeScopeResponse(scope: row.dto(), created: false)
        }

        // The chain-non-null tier ladder: a session-tier scope fills its
        // own FK and every ancestor uuid, so list/get by any ancestor stays
        // a plain indexed WHERE (m0010 grammar, ported by m0013).
        guard let lineage = try SessionLineage.request(sessionUuid: req.sessionUuid).fetchOne(db) else {
            throw StoreError.corruptState(
                entity: "session",
                detail: "session \(req.sessionUuid) has no instance->project lineage"
            )
        }
        let uuid = try core.insertBase(
            db,
            table: "dope_scope",
            extra: [
                "project_uuid": lineage.projectUuid,
                "instance_uuid": lineage.instanceUuid,
                "session_uuid": req.sessionUuid,
                "prompt_uuid": req.promptUuid,
                "scope_type": scopeType.rawValue,
                "code": req.code,
                "name": req.name,
                "description": description,
                "revision": 0,
            ]
        )

        if req.cloneFromSessionBase == true {
            try cloneSessionBase(req, into: uuid)
        }

        guard let scope = try fetchDopeScope(uuid: uuid) else {
            throw StoreError.corruptState(entity: "dope_scope", detail: "vanished after insert")
        }
        try recordDopeChange(
            scope: scope,
            action: "init",
            level: .scope,
            nodeUuid: uuid,
            revision: scope.revision
        )
        return DopeScopeResponse(scope: scope, created: true)
    }

    /// Validates a scope init request: code, description length, session, and prompt ownership.
    ///
    /// - Parameter req: The initialization request.
    /// - Returns: The description to store, empty when the request carries none.
    /// - Throws: `StoreError.badRequest` or `StoreError.notFound` when the request is invalid.
    private func validateDopeInit(_ req: DopeInitRequest) throws -> String {
        try DopeCode.validateCode(req.code, field: "scope code")
        let description = req.description ?? ""
        guard description.count <= 512 else {
            throw StoreError.badRequest(detail: "scope description exceeds 512 characters")
        }
        guard try SessionRecord.all().withUuid(req.sessionUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: "session", key: req.sessionUuid)
        }
        if let promptUuid = req.promptUuid {
            guard
                let owner =
                    try PromptRecord
                    .all()
                    .withUuid(promptUuid)
                    .select(PromptRecord.Columns.sessionUuid, as: String.self)
                    .fetchOne(db)
            else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
            guard owner == req.sessionUuid else {
                throw StoreError.badRequest(
                    detail: "prompt \(promptUuid) does not belong to session \(req.sessionUuid)"
                )
            }
        }
        return description
    }

    /// Fetches the scope an init request would create, if it already exists.
    ///
    /// - Parameters:
    ///   - req: The initialization request.
    ///   - scopeType: The scope type the request resolves to.
    /// - Returns: The existing scope record, or nil when none matches.
    /// - Throws: Store errors if the query fails.
    private func existingDopeScope(
        _ req: DopeInitRequest,
        scopeType: DopeScopeType
    ) throws -> DopeScopeRecord? {
        var existing =
            DopeScopeRecord
            .filter(DopeScopeRecord.Columns.sessionUuid == req.sessionUuid)
            .filter(DopeScopeRecord.Columns.scopeType == scopeType.rawValue)
            .filter(DopeScopeRecord.Columns.code == req.code)
        if let promptUuid = req.promptUuid {
            existing = existing.filter(DopeScopeRecord.Columns.promptUuid == promptUuid)
        }
        return try existing.fetchOne(db)
    }

    /// Copies the same-coded SESSION_INSTANCE scope's tree into a freshly created prompt scope.
    ///
    /// - Parameters:
    ///   - req: The initialization request.
    ///   - uuid: The uuid of the newly inserted scope.
    /// - Throws: `StoreError.badRequest` if the scope is not a prompt scope or no base exists.
    private func cloneSessionBase(_ req: DopeInitRequest, into uuid: String) throws {
        guard req.promptUuid != nil else {
            throw StoreError.badRequest(
                detail: "--clone-from-session-base is only meaningful for a PROMPT scope"
            )
        }
        guard
            let baseRow =
                try DopeScopeRecord
                .filter(DopeScopeRecord.Columns.sessionUuid == req.sessionUuid)
                .filter(
                    DopeScopeRecord.Columns.scopeType == DopeScopeType.sessionInstance.rawValue
                )
                .filter(DopeScopeRecord.Columns.code == req.code)
                .fetchOne(db)
        else {
            throw StoreError.badRequest(
                detail: "no SESSION_INSTANCE scope with code '\(req.code)' to clone from"
            )
        }
        _ = try copyDopeTree(from: baseRow.dto(), into: uuid)
    }

    // MARK: - Read-verb guards + shared candidate query

    /// Validates that a session and optional prompt exist.
    ///
    /// Hoisted from dopeInit to let read verbs distinguish an unknown uuid (NOT_FOUND) from a
    /// real but uninitialized target (SUMMARY_ABSENT). Used by the clarify/arch/explore/review
    /// get pattern. Skips the ownership check that dopeInit performs.
    ///
    /// - Parameters:
    ///   - sessionUuid: The session uuid to validate.
    ///   - promptUuid: The optional prompt uuid to validate.
    /// - Throws: `StoreError.notFound` if the session or prompt not found.
    private func requireDopeTarget(
        sessionUuid: String,
        promptUuid: String?
    ) throws {
        guard try SessionRecord.all().withUuid(sessionUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: "session", key: sessionUuid)
        }
        if let promptUuid {
            guard try PromptRecord.all().withUuid(promptUuid).fetchCount(db) > 0 else {
                throw StoreError.notFound(entity: "prompt", key: promptUuid)
            }
        }
    }

    /// Fetches dope scope candidates matching session, type, prompt, and optional code.
    ///
    /// Shared by dopeGet's resolution ladder and dopeList's enumeration. One copy keeps the
    /// picker's row order and BAD_REQUEST candidate order identical (ORDER BY code). Internal
    /// (not private): Store+Diagram's binding resolution reuses this exact ladder query.
    ///
    /// - Parameters:
    ///   - sessionUuid: The session uuid.
    ///   - scopeType: The scope type to filter by.
    ///   - promptUuid: The optional prompt uuid; required when scope type is .sessionInstanceItem.
    ///   - code: The optional scope code to filter by.
    /// - Returns: Array of matching scope rows, ordered by code.
    /// - Throws: Store errors if the query fails.
    func dopeScopeCandidates(
        sessionUuid: String,
        scopeType: DopeScopeType,
        promptUuid: String? = nil,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        var request =
            DopeScopeRecord
            .filter(DopeScopeRecord.Columns.sessionUuid == sessionUuid)
            .filter(DopeScopeRecord.Columns.scopeType == scopeType.rawValue)
        if scopeType == .sessionInstanceItem {
            // `== nil` compiles to IS NULL, which MATCHES the prompt-less rows.
            // The retired SQL bound a nil parameter, where `= NULL` matched
            // nothing; nil means "no candidates" and has to stay that way.
            guard let promptUuid else { return [] }
            request = request.filter(DopeScopeRecord.Columns.promptUuid == promptUuid)
        }
        if let code {
            request = request.filter(DopeScopeRecord.Columns.code == code)
        }
        return
            try request
            .order(DopeScopeRecord.Columns.code)
            .fetchAll(db)
            .map { $0.dto() }
    }

    /// Fetches project-tier dope scope candidates.
    ///
    /// `dopeScopeCandidates` cannot address BASE_PROJECT scopes (session_uuid-based filter).
    /// PROJECT_ITEM is the masking tier over BASE_PROJECT, mirroring SESSION_INSTANCE_ITEM
    /// over SESSION_INSTANCE. Without this, project-tier diagrams would resolve nothing.
    ///
    /// - Parameters:
    ///   - projectUuid: The project uuid.
    ///   - scopeType: The scope type to filter by.
    ///   - code: The optional scope code to filter by.
    /// - Returns: Array of matching scope rows, ordered by code.
    /// - Throws: Store errors if the query fails.
    func dopeProjectScopeCandidates(
        projectUuid: String,
        scopeType: DopeScopeType,
        code: String? = nil
    ) throws -> [DopeScopeRow] {
        var request =
            DopeScopeRecord
            .filter(DopeScopeRecord.Columns.projectUuid == projectUuid)
            .filter(DopeScopeRecord.Columns.scopeType == scopeType.rawValue)
            .filter(DopeScopeRecord.Columns.sessionUuid == nil)
        if let code {
            request = request.filter(DopeScopeRecord.Columns.code == code)
        }
        return
            try request
            .order(DopeScopeRecord.Columns.code)
            .fetchAll(db)
            .map { $0.dto() }
    }

    // MARK: - List (v12; picker enumeration — never a PROMPT/SESSION_INSTANCE union)

    /// Lists dope scopes for a session or prompt.
    /// - Parameter req: The list request with session, optional prompt, and optional scope code.
    /// - Returns: A response with the matching scopes.
    /// - Throws: Validation errors if session or prompt not found.
    func dopeList(_ req: DopeListRequest) throws -> DopeListResponse {
        try requireDopeTarget(
            sessionUuid: req.sessionUuid,
            promptUuid: req.promptUuid
        )
        let scopes: [DopeScopeRow]
        if let promptUuid = req.promptUuid {
            scopes = try dopeScopeCandidates(
                sessionUuid: req.sessionUuid,
                scopeType: .sessionInstanceItem,
                promptUuid: promptUuid
            )
        } else {
            scopes = try dopeScopeCandidates(
                sessionUuid: req.sessionUuid,
                scopeType: .sessionInstance
            )
        }
        return DopeListResponse(scopes: scopes)
    }

    // MARK: - Get (PROMPT → SESSION_INSTANCE fallback)

    /// Fetches a dope tree with optional overlay resolution.
    /// - Parameter req: The get request with session, optional prompt, project, and scope code.
    /// - Returns: A response with the tree and resolution information.
    /// - Throws: Validation errors if session/prompt/project not found, or multiple scopes match.
    func dopeGet(_ req: DopeGetRequest) throws -> DopeGetResponse {
        // PROJECT-tier addressing: its own two-rung ladder, mirroring
        // the session one. Reached by a project-tier diagram's bindings
        // and by a DOPE_GET carrying project_uuid.
        if let projectUuid = req.projectUuid {
            return try dopeGetProject(req, projectUuid: projectUuid)
        }

        try requireDopeTarget(
            sessionUuid: req.sessionUuid,
            promptUuid: req.promptUuid
        )

        let (scope, resolvedVia) = try resolveSessionScope(req)
        let tree = try fetchDopeTree(scope: scope)

        // Unresolved is the default and is byte-identical to pre-resolver
        // behavior — every existing caller is untouched.
        let areas = try areaVersions(scopeUuid: scope.uuid)

        guard req.resolved == true, let tier = scope.tier, tier.isOverlay,
            let baseTier = tier.masks
        else {
            return DopeGetResponse(
                tree: tree,
                resolvedVia: resolvedVia,
                areaVersions: areas
            )
        }

        // Base pairing is by CODE plus lineage, needing no stored pointer:
        // an overlay masks the same-coded scope one tier up. A missing
        // base is legal — the overlay resolves alone, warned.
        // Tier-aware: a SESSION_INSTANCE_ITEM masks its session's base,
        // but a PROJECT_ITEM masks a PROJECT-tier base that has no
        // session at all. Keying both off session_uuid would throw on the
        // project pair.
        let baseRows = try baseScopeRows(of: scope, at: baseTier)
        let baseTree = try baseRows.first.map { try fetchDopeTree(scope: $0) }
        let merged = DopeOverlay.resolve(base: baseTree, overlay: tree)
        return DopeGetResponse(
            tree: merged.tree,
            resolvedVia: "\(tier.rawValue.lowercased())_over_\(baseTier.rawValue.lowercased())",
            resolutions: merged.resolutions.values.sorted { $0.path < $1.path },
            hidden: merged.hidden.sorted(),
            warnings: merged.warnings,
            areaVersions: areas
        )
    }

    /// Returns the single candidate scope, refusing an ambiguous match.
    ///
    /// - Parameter rows: The candidate scope rows.
    /// - Returns: The only row, or nil when there are none.
    /// - Throws: `StoreError.badRequest` when more than one row matches.
    private func pickSingleScope(_ rows: [DopeScopeRow]) throws -> DopeScopeRow? {
        if rows.count > 1 {
            throw StoreError.badRequest(
                detail:
                    "several dope scopes match — pass --code (candidates: "
                    + rows.map(\.code).joined(separator: ", ") + ")"
            )
        }
        return rows.first
    }

    /// Resolves a project-addressed get: PROJECT_ITEM first, then BASE_PROJECT.
    ///
    /// - Parameters:
    ///   - req: The get request.
    ///   - projectUuid: The project uuid the request addresses.
    /// - Returns: The unresolved tree and the rung it was found on.
    /// - Throws: `StoreError.badRequest`, `StoreError.notFound`, or `dopeProjectScopeAbsent`.
    private func dopeGetProject(
        _ req: DopeGetRequest,
        projectUuid: String
    ) throws -> DopeGetResponse {
        guard req.sessionUuid.isEmpty else {
            throw StoreError.badRequest(
                detail: "pass --project-uuid OR --session-uuid, not both"
            )
        }
        guard try ProjectRecord.all().withUuid(projectUuid).fetchCount(db) > 0 else {
            throw StoreError.notFound(entity: "project", key: projectUuid)
        }
        var projectVia = "base_project"
        var found = try pickSingleScope(
            try dopeProjectScopeCandidates(
                projectUuid: projectUuid,
                scopeType: .projectItem,
                code: req.code
            )
        )
        if found != nil { projectVia = "project_item" }
        if found == nil {
            found = try pickSingleScope(
                try dopeProjectScopeCandidates(
                    projectUuid: projectUuid,
                    scopeType: .baseProject,
                    code: req.code
                )
            )
        }
        guard let scope = found else {
            throw StoreError.dopeProjectScopeAbsent(
                projectUuid: projectUuid,
                code: req.code
            )
        }
        return DopeGetResponse(
            tree: try fetchDopeTree(scope: scope),
            resolvedVia: projectVia
        )
    }

    /// Resolves a session-addressed get: the prompt scope first, then the session base.
    ///
    /// - Parameter req: The get request, whose target has already been validated.
    /// - Returns: The resolved scope and the rung it was found on.
    /// - Throws: `StoreError.badRequest` on ambiguity, `dopeScopeAbsent` when nothing matches.
    private func resolveSessionScope(
        _ req: DopeGetRequest
    ) throws -> (scope: DopeScopeRow, resolvedVia: String) {
        var resolvedVia = "session_base"
        var scope: DopeScopeRow?
        if let promptUuid = req.promptUuid {
            scope = try pickSingleScope(
                try dopeScopeCandidates(
                    sessionUuid: req.sessionUuid,
                    scopeType: .sessionInstanceItem,
                    promptUuid: promptUuid,
                    code: req.code
                )
            )
            if scope != nil { resolvedVia = "prompt" }
        }
        if scope == nil {
            scope = try pickSingleScope(
                try dopeScopeCandidates(
                    sessionUuid: req.sessionUuid,
                    scopeType: .sessionInstance,
                    code: req.code
                )
            )
        }
        guard let scope else {
            // The target exists (guard above) — this absence means
            // "initialize a scope", not "the uuid is unknown".
            throw StoreError.dopeScopeAbsent(
                sessionUuid: req.sessionUuid,
                promptUuid: req.promptUuid,
                code: req.code
            )
        }
        return (scope, resolvedVia)
    }

    /// The scope an overlay masks: same code, one tier up.
    ///
    /// A session-owned base is addressed through the session, a project-tier
    /// one through the project, which has no session at all.
    ///
    /// - Parameters:
    ///   - scope: The overlay scope row.
    ///   - baseTier: The tier of the base scope to find.
    /// - Returns: The rows for scopes at the base tier with the same code.
    /// - Throws: Store errors if the query fails.
    private func baseScopeRows(
        of scope: DopeScopeRow,
        at baseTier: DopeScopeType
    ) throws -> [DopeScopeRow] {
        guard baseTier.isSessionOwned else {
            return
                try DopeScopeRecord
                .filter(DopeScopeRecord.Columns.projectUuid == scope.projectUuid)
                .filter(DopeScopeRecord.Columns.scopeType == baseTier.rawValue)
                .filter(DopeScopeRecord.Columns.code == scope.code)
                .order(DopeScopeRecord.Columns.code)
                .fetchAll(db)
                .map { $0.dto() }
        }
        return try dopeScopeCandidates(
            sessionUuid: try scope.requireSessionUuid(),
            scopeType: baseTier,
            code: scope.code
        )
    }

    /// Fetches the persistence uuid that owns a node at the given level.
    ///
    /// Mirrors dopeOwningScope's join chain, stopping one level short. Returns nil for
    /// scope-level nodes.
    ///
    /// - Parameters:
    ///   - level: The level of the node.
    ///   - nodeUuid: The node uuid.
    /// - Returns: The owning persistence uuid, or nil for scope-level nodes.
    /// - Throws: Store errors if the query fails.
    func owningPersistenceUuid(
        level: DopeLevel,
        nodeUuid: String
    ) throws -> String? {
        let column = DopePersistenceEntityRecord.Columns.dopePersistenceUuid
        switch level {
        case .scope: return nil
        case .persistence: return nodeUuid
        case .entity:
            return
                try DopePersistenceEntityRecord
                .all()
                .withUuid(nodeUuid)
                .select(column, as: String.self)
                .fetchOne(db)
        case .enumeration:
            return
                try DopePersistenceEnumRecord
                .all()
                .withUuid(nodeUuid)
                .select(DopePersistenceEnumRecord.Columns.dopePersistenceUuid, as: String.self)
                .fetchOne(db)
        case .property:
            return
                try DopePersistenceEntityRecord
                .joining(
                    required: DopePersistenceEntityRecord.properties.unordered()
                        .withUuid(nodeUuid)
                )
                .select(column, as: String.self)
                .fetchOne(db)
        case .option:
            return
                try DopePersistenceEnumRecord
                .joining(
                    required: DopePersistenceEnumRecord.options.unordered().withUuid(nodeUuid)
                )
                .select(DopePersistenceEnumRecord.Columns.dopePersistenceUuid, as: String.self)
                .fetchOne(db)
        }
    }

    /// Fetches per-area content counters derived from the max content_revision in each area.
    ///
    /// Computed rather than stored on the scope to reduce columns. The query a client actually
    /// needs is the maximum content_revision per area.
    ///
    /// - Parameter scopeUuid: The scope uuid.
    /// - Returns: A dictionary mapping area names to their max revision.
    /// - Throws: Store errors if the query fails.
    func areaVersions(scopeUuid: String) throws -> [String: Int64] {
        var out: [String: Int64] = [:]
        for area in DopeArea.allCases {
            out[area.rawValue] =
                try Table(area.table)
                .filter(Column("dope_scope_uuid") == scopeUuid)
                .select(max(Column("content_revision")) ?? 0, as: Int64.self)
                .fetchOne(db) ?? 0
        }
        return out
    }

    // MARK: - Hydration (five flat queries, grouped in Swift — never per-node
    // recursion; ORDER BY sort_order, code keeps write-repo deterministic)

    /// Fetches the complete domain and enumeration tree for a scope.
    ///
    /// `forProjection` makes every level filter `deleted_on IS NULL`. Reads
    /// deliberately return tombstoned rows for the masking resolver. The db → files
    /// projection must not, since tombstones are personal overlay-tier state while
    /// .doped.json is shared fact. That filter is defence in depth over
    /// `dopeNodeDelete`'s soft-delete tier check and `requireRepoWritableScope`,
    /// surviving either being relaxed.
    ///
    /// - Parameters:
    ///   - scope: The scope row to fetch the tree for.
    ///   - forProjection: When true, filters out soft-deleted rows; defaults to false.
    /// - Returns: The assembled dope scope tree with all domains, entities, properties, and enums.
    /// - Throws: Store errors if the queries fail.
    func fetchDopeTree(
        scope: DopeScopeRow,
        forProjection: Bool = false
    ) throws -> DopeScopeTree {
        let rows = try dopeTreeRows(scopeUuid: scope.uuid, forProjection: forProjection)
        return DopeScopeTree(
            identity: DopeNodeIdentity(
                uuid: scope.uuid,
                version: scope.version,
                createdAt: scope.createdAt,
                updatedAt: scope.updatedAt
            ),
            body: DopeScopeBody(
                code: scope.code,
                name: scope.name,
                description: scope.description
            ),
            sessionUuid: scope.sessionUuid,
            promptUuid: scope.promptUuid,
            scopeType: scope.scopeType,
            revision: scope.revision,
            domains: Self.domainNodes(rows, refs: Self.treeRefs(rows))
        )
    }

    /// Fetches the five flat reads that comprise a dope tree.
    ///
    /// Five SQL statements grouped in Swift, never per-node recursion or prefetch. The folds
    /// that follow need every level as one flat list to resolve cross-level references.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope uuid.
    ///   - live: When true, filters out soft-deleted rows.
    /// - Returns: A tuple with arrays for each level: domains, entities, properties, enums, options.
    /// - Throws: Store errors if any query fails.
    private func dopeTreeRows(
        scopeUuid: String,
        forProjection live: Bool
    ) throws -> DopeTreeRows {
        let inScope = DopePersistenceRecord.Columns.dopeScopeUuid == scopeUuid
        let domain = DopePersistenceEntityRecord.dopePersistence.notDeleted(live).filter(inScope)
        let enumDomain = DopePersistenceEnumRecord.dopePersistence.notDeleted(live).filter(inScope)
        return DopeTreeRows(
            domains:
                try DopePersistenceRecord
                .filter(inScope)
                .notDeleted(live)
                .order(
                    DopePersistenceRecord.Columns.sortOrder,
                    DopePersistenceRecord.Columns.code
                )
                .fetchAll(db),
            entities:
                try DopePersistenceEntityRecord
                .joining(required: domain)
                .notDeleted(live)
                .order(
                    DopePersistenceEntityRecord.Columns.sortOrder,
                    DopePersistenceEntityRecord.Columns.code
                )
                .fetchAll(db),
            enums:
                try DopePersistenceEnumRecord
                .joining(required: enumDomain)
                .notDeleted(live)
                .order(
                    DopePersistenceEnumRecord.Columns.sortOrder,
                    DopePersistenceEnumRecord.Columns.code
                )
                .fetchAll(db),
            options:
                try DopePersistenceEnumOptionRecord
                .joining(
                    required: DopePersistenceEnumOptionRecord.dopeEnum
                        .notDeleted(live)
                        .joining(required: enumDomain)
                )
                .notDeleted(live)
                .order(
                    DopePersistenceEnumOptionRecord.Columns.sortOrder,
                    DopePersistenceEnumOptionRecord.Columns.code
                )
                .fetchAll(db),
            properties:
                try DopePersistenceEntityPropertyRecord
                .joining(
                    required: DopePersistenceEntityPropertyRecord.entity
                        .notDeleted(live)
                        .joining(required: domain)
                )
                .notDeleted(live)
                .order(
                    DopePersistenceEntityPropertyRecord.Columns.sortOrder,
                    DopePersistenceEntityPropertyRecord.Columns.code
                )
                .fetchAll(db)
        )
    }

    /// The five levels of one tree, flat.
    private struct DopeTreeRows {
        var domains: [DopePersistenceRecord]
        var entities: [DopePersistenceEntityRecord]
        var enums: [DopePersistenceEnumRecord]
        var options: [DopePersistenceEnumOptionRecord]
        var properties: [DopePersistenceEntityPropertyRecord]
    }

    /// uuid → dot-path code, per level.
    ///
    /// Cross-level refs are stored as uuids and projected as codes, so every
    /// ref needs its target's ancestry.
    private struct DopeTreeRefs {
        var entity: [String: String] = [:]
        var dopeEnum: [String: String] = [:]
        var property: [String: String] = [:]
    }

    /// Builds uuid-to-dot-path reference maps for all rows in a tree.
    ///
    /// - Parameter rows: The flat tree rows from `dopeTreeRows`.
    /// - Returns: Maps of uuids to dot-path codes for entities, enums, and properties.
    private static func treeRefs(_ rows: DopeTreeRows) -> DopeTreeRefs {
        var refs = DopeTreeRefs()
        var domainCode: [String: String] = [:]
        for row in rows.domains { domainCode[row.uuid] = row.code }
        var entityInfo: [String: (domain: String, code: String)] = [:]
        for row in rows.entities {
            let domain = domainCode[row.dopePersistenceUuid] ?? "?"
            entityInfo[row.uuid] = (domain, row.code)
            refs.entity[row.uuid] = DopeCode.formatEntityRef(domain: domain, entity: row.code)
        }
        for row in rows.enums {
            let domain = domainCode[row.dopePersistenceUuid] ?? "?"
            refs.dopeEnum[row.uuid] = DopeCode.formatEnumRef(domain: domain, enumCode: row.code)
        }
        for row in rows.properties {
            let info = entityInfo[row.dopePersistenceEntityUuid] ?? (domain: "?", code: "?")
            refs.property[row.uuid] = DopeCode.formatPropertyRef(
                domain: info.domain,
                entity: info.code,
                property: row.code
            )
        }
        return refs
    }

    /// Assembles domain nodes with nested entities, enums, and properties.
    ///
    /// - Parameters:
    ///   - rows: The flat tree rows from `dopeTreeRows`.
    ///   - refs: The uuid-to-code reference maps from `treeRefs`.
    /// - Returns: The assembled domain nodes with fully nested hierarchies.
    private static func domainNodes(
        _ rows: DopeTreeRows,
        refs: DopeTreeRefs
    ) -> [DopePersistenceNode] {
        let propertiesByEntity = propertyNodesByEntity(rows, refs: refs)
        let optionsByEnum = optionNodesByEnum(rows)
        let entitiesByDomain = entityNodesByDomain(
            rows,
            refs: refs,
            propertiesByEntity: propertiesByEntity
        )
        let enumsByDomain = enumNodesByDomain(rows, optionsByEnum: optionsByEnum)
        return rows.domains.map { row in
            DopePersistenceNode(
                identity: row.identity(),
                body: DopePersistenceBody(
                    code: row.code,
                    name: row.name,
                    description: row.description,
                    sortOrder: Int(row.sortOrder)
                ),
                entities: entitiesByDomain[row.uuid] ?? [],
                enums: enumsByDomain[row.uuid] ?? []
            )
        }
    }

    /// Groups property nodes by owning entity uuid.
    ///
    /// - Parameters:
    ///   - rows: The flat tree rows from `dopeTreeRows`.
    ///   - refs: The uuid-to-code reference maps from `treeRefs`.
    /// - Returns: Property nodes keyed by entity uuid, in row order.
    private static func propertyNodesByEntity(
        _ rows: DopeTreeRows,
        refs: DopeTreeRefs
    ) -> [String: [DopePropertyNode]] {
        var propertiesByEntity: [String: [DopePropertyNode]] = [:]
        for row in rows.properties {
            propertiesByEntity[row.dopePersistenceEntityUuid, default: []]
                .append(
                    DopePropertyNode(
                        identity: row.identity(),
                        body: DopePropertyBody(
                            code: row.code,
                            name: row.name,
                            description: row.description,
                            sortOrder: Int(row.sortOrder),
                            dataType: row.dataType,
                            nullable: row.nullable,
                            isUnique: row.isUnique,
                            autoIncrement: row.autoIncrement,
                            textCharLimit: row.textCharLimit.map(Int.init),
                            enumRef: row.dopePersistenceEnumUuid.flatMap { refs.dopeEnum[$0] },
                            relationshipTargetRef: row.relationshipTargetUuid
                                .flatMap { refs.property[$0] },
                            baseOriginRef: row.baseOriginPropertyUuid
                                .flatMap { refs.property[$0] }
                        )
                    )
                )
        }
        return propertiesByEntity
    }

    /// Groups option nodes by owning enum uuid.
    ///
    /// - Parameter rows: The flat tree rows from `dopeTreeRows`.
    /// - Returns: Option nodes keyed by enum uuid, in row order.
    private static func optionNodesByEnum(_ rows: DopeTreeRows) -> [String: [DopeOptionNode]] {
        var optionsByEnum: [String: [DopeOptionNode]] = [:]
        for row in rows.options {
            optionsByEnum[row.dopePersistenceEnumUuid, default: []]
                .append(
                    DopeOptionNode(
                        identity: row.identity(),
                        body: DopeOptionBody(
                            code: row.code,
                            name: row.name,
                            description: row.description,
                            sortOrder: Int(row.sortOrder)
                        )
                    )
                )
        }
        return optionsByEnum
    }

    /// Groups entity nodes, each carrying its properties, by owning domain uuid.
    ///
    /// - Parameters:
    ///   - rows: The flat tree rows from `dopeTreeRows`.
    ///   - refs: The uuid-to-code reference maps from `treeRefs`.
    ///   - propertiesByEntity: Property nodes keyed by entity uuid.
    /// - Returns: Entity nodes keyed by domain uuid, in row order.
    private static func entityNodesByDomain(
        _ rows: DopeTreeRows,
        refs: DopeTreeRefs,
        propertiesByEntity: [String: [DopePropertyNode]]
    ) -> [String: [DopeEntityNode]] {
        var entitiesByDomain: [String: [DopeEntityNode]] = [:]
        for row in rows.entities {
            entitiesByDomain[row.dopePersistenceUuid, default: []]
                .append(
                    DopeEntityNode(
                        identity: row.identity(),
                        body: DopeEntityBody(
                            code: row.code,
                            name: row.name,
                            entityType: row.entityType,
                            description: row.description,
                            sortOrder: Int(row.sortOrder),
                            repoRepresentativeFile: row.repoRepresentativeFile,
                            baseComposableRef: row.baseComposableUuid
                                .flatMap { refs.entity[$0] }
                        ),
                        properties: propertiesByEntity[row.uuid] ?? []
                    )
                )
        }
        return entitiesByDomain
    }

    /// Groups enum nodes, each carrying its options, by owning domain uuid.
    ///
    /// - Parameters:
    ///   - rows: The flat tree rows from `dopeTreeRows`.
    ///   - optionsByEnum: Option nodes keyed by enum uuid.
    /// - Returns: Enum nodes keyed by domain uuid, in row order.
    private static func enumNodesByDomain(
        _ rows: DopeTreeRows,
        optionsByEnum: [String: [DopeOptionNode]]
    ) -> [String: [DopeEnumNode]] {
        var enumsByDomain: [String: [DopeEnumNode]] = [:]
        for row in rows.enums {
            enumsByDomain[row.dopePersistenceUuid, default: []]
                .append(
                    DopeEnumNode(
                        identity: row.identity(),
                        body: DopeEnumBody(
                            code: row.code,
                            name: row.name,
                            description: row.description,
                            sortOrder: Int(row.sortOrder),
                            repoRepresentativeFile: row.repoRepresentativeFile
                        ),
                        options: optionsByEnum[row.uuid] ?? []
                    )
                )
        }
        return enumsByDomain
    }

    /// Copies a tree between scopes, reminting child uuids.
    ///
    /// Hydrates the source tree, projects it to identity-free documents, and re-inserts into
    /// the target. Extracted verbatim from dopeInit's inline clone, so dopeInit and dopePromote
    /// share one copy path. Child uuids are reminted by insertDopeTree, which is why
    /// cross-layer references use dot-path codes rather than uuids.
    ///
    /// - Parameters:
    ///   - source: The source scope row.
    ///   - targetScopeUuid: The target scope uuid.
    /// - Returns: Counts of rows inserted at each level.
    /// - Throws: Store errors if the copy fails.
    @discardableResult
    func copyDopeTree(
        from source: DopeScopeRow,
        into targetScopeUuid: String
    ) throws -> DopeTreeCounts {
        let tree = try fetchDopeTree(scope: source)
        let bundle = DopeProjection.documents(from: tree)
        return try insertDopeTree(
            scopeUuid: targetScopeUuid,
            domainFiles: bundle.domainFiles
        )
    }

    // MARK: - Whole-tree insert (clone + ingest share it). Documents in,
    // rows out; validator-approved input assumed (callers validate first).
    // Insert order is dependency order: domains → enums → options → entities
    // → non-relationship properties → relationship properties.

    /// Inserts a complete domain tree from validated documents.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope to insert the tree into.
    ///   - domainFiles: The domain documents in arbitrary order.
    /// - Returns: Counts of rows inserted at each level.
    /// - Throws: Store errors if any insert fails or schema violations occur.
    @discardableResult
    func insertDopeTree(
        scopeUuid: String,
        domainFiles: [DopePersistenceFileDocument]
    ) throws -> DopeTreeCounts {
        var counts = (domains: 0, entities: 0, properties: 0, enums: 0, options: 0)
        var domainUuidByCode: [String: String] = [:]
        var enumUuidByRef: [String: String] = [:]
        var propertyUuidByRef: [String: String] = [:]
        var entityUuidByRef: [String: String] = [:]
        var entityRefByUuid: [String: String] = [:]
        var pendingRelationship: [(entityUuid: String, body: DopePropertyBody)] = []
        var pendingBase: [(entityUuid: String, ref: String)] = []
        var pendingBaseOrigin: [(propertyUuid: String, ref: String)] = []

        // Pass 1 — ALL domains, then ALL enums + options, across every file
        // BEFORE any property is inserted: enum refs are cross-domain-capable
        // and domain files arrive in arbitrary (alphabetical) order, so a
        // per-domain forward pass would miss a ref into a later domain and
        // write NULL into a CHECK-coupled column.
        for file in domainFiles {
            let domainUuid = try core.insertBase(
                db,
                table: "dope_persistence",
                extra: [
                    "dope_scope_uuid": scopeUuid,
                    "code": file.body.code, "name": file.body.name,
                    "description": file.body.description, "sort_order": file.body.sortOrder,
                ]
            )
            counts.domains += 1
            domainUuidByCode[file.body.code] = domainUuid
        }
        for file in domainFiles {
            let domainUuid = domainUuidByCode[file.body.code]!
            for en in file.enums {
                let enumUuid = try core.insertBase(
                    db,
                    table: "dope_persistence_enum",
                    extra: [
                        "dope_persistence_uuid": domainUuid,
                        "code": en.body.code, "name": en.body.name,
                        "description": en.body.description, "sort_order": en.body.sortOrder,
                        "repo_representative_file": en.body.repoRepresentativeFile,
                    ]
                )
                counts.enums += 1
                enumUuidByRef[
                    DopeCode.formatEnumRef(
                        domain: file.body.code,
                        enumCode: en.body.code
                    )
                ] = enumUuid
                for option in en.options {
                    _ = try core.insertBase(
                        db,
                        table: "dope_persistence_enum_option",
                        extra: [
                            "dope_persistence_enum_uuid": enumUuid,
                            "code": option.body.code, "name": option.body.name,
                            "description": option.body.description,
                            "sort_order": option.body.sortOrder,
                        ]
                    )
                    counts.options += 1
                }
            }
        }

        // Pass 2 — entities + non-relationship properties (every enum target
        // now exists; a missed enum lookup is a loud error, never a NULL).
        for file in domainFiles {
            let domainUuid = domainUuidByCode[file.body.code]!
            for entity in file.entities {
                let entityUuid = try core.insertBase(
                    db,
                    table: "dope_persistence_entity",
                    extra: [
                        "dope_persistence_uuid": domainUuid,
                        "code": entity.body.code, "name": entity.body.name,
                        "entity_type": entity.body.entityType,
                        "description": entity.body.description,
                        "sort_order": entity.body.sortOrder,
                        "repo_representative_file": entity.body.repoRepresentativeFile,
                    ]
                )
                counts.entities += 1
                let entityRef = DopeCode.formatEntityRef(
                    domain: file.body.code,
                    entity: entity.body.code
                )
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
                                detail: "enum property '\(body.code)' ref '\(enumRef)' did not resolve during insert"
                            )
                        }
                        enumUuid = resolved
                    }
                    let uuid = try core.insertBase(
                        db,
                        table: "dope_persistence_entity_property",
                        extra: [
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
                        ]
                    )
                    counts.properties += 1
                    propertyUuidByRef[
                        DopeCode.formatPropertyRef(
                            domain: file.body.code,
                            entity: entity.body.code,
                            property: body.code
                        )
                    ] = uuid
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
                    detail: "entity base_composable_ref '\(pending.ref)' did not resolve during insert"
                )
            }
            try db.execute(
                sql: "UPDATE dope_persistence_entity SET base_composable_uuid = ? WHERE uuid = ?",
                arguments: [target, pending.entityUuid]
            )
        }
        // Relationship properties last: the validator bans chain refs, so
        // every target is a non-relationship property inserted above.
        for pending in pendingRelationship {
            let body = pending.body
            guard let ref = body.relationshipTargetRef,
                let target = propertyUuidByRef[ref]
            else {
                throw StoreError.badRequest(
                    detail:
                        "relationship property '\(body.code)' target '\(body.relationshipTargetRef ?? "nil")' did not resolve during insert"
                )
            }
            let uuid = try core.insertBase(
                db,
                table: "dope_persistence_entity_property",
                extra: [
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
                ]
            )
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
                    detail: "property base_origin_ref '\(pending.ref)' did not resolve during insert"
                )
            }
            try db.execute(
                sql: """
                    UPDATE dope_persistence_entity_property SET base_origin_property_uuid = ? WHERE uuid = ?
                    """,
                arguments: [target, pending.propertyUuid]
            )
        }
        return DopeTreeCounts(
            domains: counts.domains,
            entities: counts.entities,
            properties: counts.properties,
            enums: counts.enums,
            options: counts.options
        )
    }

    /// Updates scope metadata and revision atomically during an ingest.
    ///
    /// The WHERE carries `expectedRevision`, so a concurrent writer loses the
    /// race cleanly; the CASE bumps `version` only when name or description
    /// actually move, leaving a pure tree ingest's optimistic lock alone.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope uuid to update.
    ///   - incoming: The new revision number from the ingest.
    ///   - expectedRevision: The revision the caller last read; fail if stale.
    ///   - name: The new scope name.
    ///   - description: The new scope description.
    /// - Throws: `StoreError.revisionConflict` if `expectedRevision` is stale.
    func applyIngestedScope(
        scopeUuid: String,
        incoming: Int64,
        expectedRevision: Int64,
        name: String,
        description: String
    ) throws {
        try db.execute(
            sql: """
                UPDATE dope_scope
                   SET revision = ?,
                       name = ?,
                       description = ?,
                       version = version + (CASE WHEN name IS NOT ? OR description IS NOT ?
                                                 THEN 1 ELSE 0 END),
                       updated_at = ?
                 WHERE uuid = ? AND revision = ?
                """,
            arguments: [
                incoming,
                name, description,
                name, description,
                Store.isoNow(), scopeUuid, expectedRevision,
            ]
        )
        guard db.changesCount == 0 else { return }
        guard
            let actual =
                try DopeScopeRecord
                .all()
                .withUuid(scopeUuid)
                .select(DopeScopeRecord.Columns.revision, as: Int64.self)
                .fetchOne(db)
        else {
            throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
        }
        throw StoreError.revisionConflict(
            scopeUuid: scopeUuid,
            expected: expectedRevision,
            actual: actual
        )
    }

    /// Deletes all persistence, domains, entities, properties, enums, and options in a scope.
    ///
    /// The ordered delete handles relationship properties first, then remaining
    /// properties, then domains; CASCADE clears entities, enums, and options.
    /// Never rely on CASCADE to unwind a RESTRICT.
    ///
    /// - Parameter scopeUuid: The scope uuid to wipe.
    /// - Throws: Store errors if any delete fails or constraint checks fail.
    func wipeDopeTree(scopeUuid: String) throws {
        // Entities compose each other under an ON DELETE RESTRICT self-FK, so
        // un-link every base BEFORE the domain CASCADE reaches the rows — a
        // base pair inside one domain would otherwise trip the RESTRICT
        // mid-statement. Rows about to be deleted; version deliberately
        // untouched.
        try db.execute(
            sql: """
                UPDATE dope_persistence_entity SET base_composable_uuid = NULL
                 WHERE base_composable_uuid IS NOT NULL
                   AND dope_persistence_uuid IN (
                    SELECT uuid FROM dope_persistence WHERE dope_scope_uuid = ?)
                """,
            arguments: [scopeUuid]
        )
        // base_origin is data_type-INDEPENDENT, so the relationship-first
        // DELETE split below cannot separate origin referrers from their
        // targets — NULL every tag before either property DELETE runs.
        try db.execute(
            sql: """
                UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
                 WHERE base_origin_property_uuid IS NOT NULL
                   AND dope_persistence_entity_uuid IN (
                    SELECT e.uuid FROM dope_persistence_entity e
                      JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                     WHERE d.dope_scope_uuid = ?)
                """,
            arguments: [scopeUuid]
        )
        try db.execute(
            sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE data_type = 'relationship'
                   AND dope_persistence_entity_uuid IN (
                    SELECT e.uuid FROM dope_persistence_entity e
                      JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                     WHERE d.dope_scope_uuid = ?)
                """,
            arguments: [scopeUuid]
        )
        try db.execute(
            sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE dope_persistence_entity_uuid IN (
                    SELECT e.uuid FROM dope_persistence_entity e
                      JOIN dope_persistence d ON d.uuid = e.dope_persistence_uuid
                     WHERE d.dope_scope_uuid = ?)
                """,
            arguments: [scopeUuid]
        )
        try db.execute(
            sql: "DELETE FROM dope_persistence WHERE dope_scope_uuid = ?",
            arguments: [scopeUuid]
        )
        // Cogs go in the SAME wipe: an ingest that replaced persistence but
        // left cogs behind would leave the two areas describing different
        // revisions of the tree.
        try db.execute(
            sql: "DELETE FROM dope_cog WHERE dope_scope_uuid = ?",
            arguments: [scopeUuid]
        )
    }

    /// Inserts cogs from an ingested bundle, expanding persistence owner links.
    ///
    /// Each hull's collapsed `links.persistence_owners` are expanded back into
    /// sibling PersistenceOwner element rows.
    ///
    /// - Parameters:
    ///   - scopeUuid: The scope to insert cogs into.
    ///   - cogFiles: The cog documents to insert.
    /// - Throws: Store errors if any insert fails.
    func insertDopeCogs(
        scopeUuid: String,
        cogFiles: [DopeCogDocument]
    ) throws {
        for (cogIndex, cog) in cogFiles.enumerated() {
            let cogUuid = try core.insertBase(
                db,
                table: "dope_cog",
                extra: [
                    "dope_scope_uuid": scopeUuid,
                    "code": cog.body.code, "name": cog.body.name,
                    "description": cog.body.description,
                    "sort_order": cog.body.sortOrder == 0 ? cogIndex : cog.body.sortOrder,
                    "content_revision": 0,
                ]
            )
            for element in cog.elements {
                let spec = try DopeCogElementSpec.spec(for: element.elementType)
                let elementUuid = try core.insertBase(
                    db,
                    table: "dope_cog_element",
                    extra: [
                        "dope_cog_uuid": cogUuid,
                        "parent_element_uuid": nil,
                        "element_type": element.elementType,
                        "code": element.code, "name": element.name,
                        "description": element.description,
                        "sort_order": element.sortOrder,
                        "dope_scope_code": element.dopeScopeCode,
                    ]
                )
                var subtype: [String: (any DatabaseValueConvertible)?] = ["element_uuid": elementUuid]
                if spec.ownedFields.contains(.primaryPath) {
                    subtype["primary_path"] = element.primaryPath ?? ""
                }
                _ = try core.insertBase(db, table: spec.subtypeTable, extra: subtype)

                // Expand the links block back into child rows, using the ONE
                // synthesis both the reader and the seeder share.
                for (i, owned) in (element.links?.persistenceOwners ?? []).enumerated() {
                    let child = DopeCogProjection.ownerElement(
                        parentCode: element.code,
                        persistenceCode: owned,
                        sortOrder: i
                    )
                    let childUuid = try core.insertBase(
                        db,
                        table: "dope_cog_element",
                        extra: [
                            "dope_cog_uuid": cogUuid,
                            "parent_element_uuid": elementUuid,
                            "element_type": DopeCogElementType.persistenceOwner.rawValue,
                            "code": child.code, "name": child.name,
                            "description": child.description,
                            "sort_order": child.sortOrder,
                            "dope_scope_code": nil,
                        ]
                    )
                    _ = try core.insertBase(
                        db,
                        table: "dope_cog_persistence_owner",
                        extra: [
                            "element_uuid": childUuid,
                            "dope_persistence_code": owned,
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Generic node mutations

    /// Validates that all provided fields are owned by the given level.
    ///
    /// - Parameters:
    ///   - fields: The node fields being validated.
    ///   - level: The level that must own each field.
    /// - Throws: `StoreError.badRequest` if a field is not owned by the level.
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
                detail: "level '\(level.rawValue)' has no field '\(field.rawValue)'"
            )
        }
    }

    /// Validates that a description does not exceed the length limit for its level.
    ///
    /// - Parameters:
    ///   - text: The description text to validate, or nil.
    ///   - level: The dope level whose description limit applies.
    /// - Throws: `StoreError.badRequest` if the text exceeds the limit.
    private func validateDopeDescription(_ text: String?, level: DopeLevel) throws {
        guard let text else { return }
        let limit = Self.dopeDescriptionLimits[level] ?? 128
        guard text.count <= limit else {
            throw StoreError.badRequest(
                detail: "\(level.rawValue) description exceeds \(limit) characters"
            )
        }
    }

    /// Validates that a property's final state is consistent and reachable.
    ///
    /// The schema CHECKs are the backstop; this produces the friendly message
    /// and enforces what SQL cannot see: same scope, no chain refs, and reachable
    /// base origins.
    ///
    /// - Parameters:
    ///   - scope: The scope the property belongs to.
    ///   - propertyUuid: The property uuid, or nil on add.
    ///   - entityUuid: The entity the property belongs to.
    ///   - dataType: The property's data type.
    ///   - enumUuid: The enum uuid for enumeration properties, nil otherwise.
    ///   - relationshipTargetUuid: The target property uuid for relationship properties.
    ///   - baseOriginPropertyUuid: The origin property uuid for materialized properties.
    ///   - autoIncrement: The auto-increment flag for long properties.
    ///   - textCharLimit: The text character limit for text properties.
    /// - Throws: `StoreError.badRequest` if any validation fails.
    private func validatePropertyShape(
        scope: DopeScopeRow,
        propertyUuid: String?,
        entityUuid: String,
        dataType: String,
        enumUuid: String?,
        relationshipTargetUuid: String?,
        baseOriginPropertyUuid: String?,
        autoIncrement: Bool?,
        textCharLimit: Int?
    ) throws {
        guard let type = DopePropertyDataType(rawValue: dataType) else {
            throw StoreError.badRequest(detail: "unknown data_type '\(dataType)'")
        }
        if (type == .enumeration) != (enumUuid != nil) {
            throw StoreError.badRequest(
                detail: "enum properties require --enum-uuid, and only enum properties may carry one"
            )
        }
        if (type == .relationship) != (relationshipTargetUuid != nil) {
            throw StoreError.badRequest(
                detail:
                    "relationship properties require --related-property-uuid, and only relationship properties may carry one"
            )
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
                    detail: "enum \(enumUuid) belongs to a different dope scope"
                )
            }
        }
        if let relationshipTargetUuid {
            try validateRelationshipTarget(
                scope: scope,
                relationshipTargetUuid: relationshipTargetUuid
            )
        }
        if let origin = baseOriginPropertyUuid {
            try validateBaseOrigin(
                scope: scope,
                propertyUuid: propertyUuid,
                entityUuid: entityUuid,
                dataType: dataType,
                origin: origin
            )
        }
    }

    /// Validates a relationship target: same scope, and not itself a relationship.
    ///
    /// - Parameters:
    ///   - scope: The scope the property belongs to.
    ///   - relationshipTargetUuid: The target property uuid.
    /// - Throws: `StoreError.badRequest` if the target is foreign or a chain ref.
    private func validateRelationshipTarget(
        scope: DopeScopeRow,
        relationshipTargetUuid: String
    ) throws {
        let owner = try dopeOwningScope(level: .property, nodeUuid: relationshipTargetUuid)
        guard owner.uuid == scope.uuid else {
            throw StoreError.badRequest(
                detail: "target property \(relationshipTargetUuid) belongs to a different dope scope"
            )
        }
        let targetType =
            try DopePersistenceEntityPropertyRecord
            .all()
            .withUuid(relationshipTargetUuid)
            .select(DopePersistenceEntityPropertyRecord.Columns.dataType, as: String.self)
            .fetchOne(db)
        if targetType == DopePropertyDataType.relationship.rawValue {
            throw StoreError.badRequest(
                detail:
                    "target property \(relationshipTargetUuid) is itself a relationship — chain refs are not allowed"
            )
        }
    }

    /// Validates a base origin: not self, same scope, on a reachable BASE_COMPOSABLE, same type.
    ///
    /// - Parameters:
    ///   - scope: The scope the property belongs to.
    ///   - propertyUuid: The property uuid, or nil on add.
    ///   - entityUuid: The entity the property belongs to.
    ///   - dataType: The property's data type.
    ///   - origin: The origin property uuid.
    /// - Throws: `StoreError.badRequest` or `StoreError.corruptState` if the origin is invalid.
    private func validateBaseOrigin(
        scope: DopeScopeRow,
        propertyUuid: String?,
        entityUuid: String,
        dataType: String,
        origin: String
    ) throws {
        if origin == propertyUuid {
            throw StoreError.badRequest(detail: "a property cannot originate from itself")
        }
        let owner = try dopeOwningScope(level: .property, nodeUuid: origin)
        guard owner.uuid == scope.uuid else {
            throw StoreError.badRequest(
                detail: "base origin property \(origin) belongs to a different dope scope"
            )
        }
        // dopeOwningScope proves existence + scope; the origin's
        // data_type, owning entity, and that entity's kind ride in on
        // one join.
        guard let row = try DopePropertyOrigin.request(propertyUuid: origin).fetchOne(db) else {
            throw StoreError.corruptState(
                entity: "dope_persistence_entity_property",
                detail: "base origin \(origin) vanished"
            )
        }
        let originEntity = row.entityUuid
        // Defense-in-depth only: every base_composable target is
        // type-checked on write and the demotion guard holds it, so this
        // fires only on corrupt or hand-edited rows.
        guard row.entityType == DopeEntityType.baseComposable.rawValue else {
            throw StoreError.badRequest(
                detail:
                    "base origin property \(origin) lives on \(originEntity), which is not a BASE_COMPOSABLE"
            )
        }
        try requireBaseChainReaches(entityUuid: entityUuid, targetUuid: originEntity)
        guard row.dataType == dataType else {
            throw StoreError.badRequest(
                detail:
                    "base origin property \(origin) is '\(row.dataType)', not '\(dataType)' — a materialized property must keep the origin's data_type"
            )
        }
    }

    /// Validates that an entity's base chain reaches a target entity.
    ///
    /// The materialization rule requires that `entityUuid` actually composes
    /// `targetUuid`, directly or through the chain. Out-degree is 1, so this is
    /// a pointer-chase walked forwards; the visited set keeps a pre-existing
    /// cycle from hanging the walk.
    ///
    /// - Parameters:
    ///   - entityUuid: The entity that must compose the target.
    ///   - targetUuid: The entity that must be in the composition chain.
    /// - Throws: `StoreError.badRequest` if the target is not in the chain.
    private func requireBaseChainReaches(
        entityUuid: String,
        targetUuid: String
    ) throws {
        var seen: Set<String> = []
        var node = try baseComposableUuid(of: entityUuid)
        while let current = node {
            if current == targetUuid { return }
            guard seen.insert(current).inserted else { break }
            node = try baseComposableUuid(of: current)
        }
        throw StoreError.badRequest(
            detail:
                "entity \(entityUuid) does not compose \(targetUuid) — a property may only be materialized from a base its entity composes"
        )
    }

    /// Validates that an entity's final state is consistent and non-cyclic.
    ///
    /// `entityUuid` is nil on add (a row nothing can reference yet). Checks
    /// same-scope base composition, acyclicity, demotion rules, and property origins.
    ///
    /// - Parameters:
    ///   - scope: The scope the entity belongs to.
    ///   - entityUuid: The entity uuid, or nil on add.
    ///   - entityType: The entity type to validate.
    ///   - baseComposableUuid: The base entity uuid for composition, or nil.
    /// - Throws: `StoreError.badRequest` if any validation fails.
    private func validateEntityShape(
        scope: DopeScopeRow,
        entityUuid: String?,
        entityType: DopeEntityType,
        baseComposableUuid: String?
    ) throws {
        if let target = baseComposableUuid {
            if target == entityUuid {
                throw StoreError.badRequest(detail: "an entity cannot compose itself")
            }
            let owner = try dopeOwningScope(level: .entity, nodeUuid: target)
            guard owner.uuid == scope.uuid else {
                throw StoreError.badRequest(
                    detail: "base entity \(target) belongs to a different dope scope"
                )
            }
            // dopeOwningScope proves existence + scope; the TYPE needs its
            // own read.
            let targetType =
                try DopePersistenceEntityRecord
                .all()
                .withUuid(target)
                .select(DopePersistenceEntityRecord.Columns.entityType, as: String.self)
                .fetchOne(db)
            guard targetType == DopeEntityType.baseComposable.rawValue else {
                throw StoreError.badRequest(
                    detail:
                        "base entity \(target) is \(targetType ?? "unknown") — only a BASE_COMPOSABLE may be composed"
                )
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
                throw StoreError.badRequest(
                    detail:
                        "cannot set entity_type \(entityType.rawValue): still composed by "
                        + referrers.joined(separator: ", ")
                )
            }
        }
        // Strand guard: this entity's materialized properties tag origins on
        // base entities the FINAL chain must still reach. Receives the final
        // (not requested) base — passing the requested value would
        // false-refuse ordinary updates. Fires on ANY base change that
        // strands a tag (clear OR re-point); no-op on add (no properties
        // yet) and self-neutralizing when the base is unchanged.
        if let entityUuid {
            let tagged = try DopeMaterializedOrigin.request(entityUuid: entityUuid).fetchAll(db)
            if !tagged.isEmpty {
                var reachable = Set<String>()
                var node = baseComposableUuid
                while let current = node, reachable.insert(current).inserted {
                    node = try self.baseComposableUuid(of: current)
                }
                let stranded = tagged.filter { !reachable.contains($0.originEntityUuid) }
                    .map(\.code)
                guard stranded.isEmpty else {
                    throw StoreError.badRequest(
                        detail:
                            "cannot change base_composable: property "
                            + stranded.joined(separator: ", ")
                            + " still originates from a base this entity would no longer compose"
                    )
                }
            }
        }
    }

    /// Validates that composing the target would not create a cycle.
    ///
    /// Chaining is allowed but must stay acyclic. Out-degree is 1 (a single
    /// nullable column), so "does the chain from target reach entity?" is a
    /// bounded pointer-chase, not a graph search. The visited set is defensive
    /// only — a pre-existing cycle cannot be reached through these guards.
    ///
    /// - Parameters:
    ///   - entityUuid: The entity being modified.
    ///   - targetUuid: The proposed base entity.
    /// - Throws: `StoreError.badRequest` if setting target as base would create a cycle.
    private func requireAcyclicBase(
        entityUuid: String,
        targetUuid: String
    ) throws {
        var seen: Set<String> = [entityUuid]
        var node: String? = targetUuid
        while let current = node {
            guard seen.insert(current).inserted else {
                if current == entityUuid {
                    throw StoreError.badRequest(
                        detail:
                            "base_composable cycle: \(entityUuid) already sits on \(targetUuid)'s base chain"
                    )
                }
                return  // corruption below us; not this mutation's cycle
            }
            node = try baseComposableUuid(of: current)
        }
    }

    /// The base entity one entity composes, or nil.
    ///
    /// Out-degree is 1, so every chain walk here is a pointer-chase over this
    /// one hop.
    ///
    /// - Parameter entityUuid: The entity uuid to query.
    /// - Returns: The base entity uuid, or nil if none.
    /// - Throws: Store errors if the query fails.
    private func baseComposableUuid(of entityUuid: String) throws -> String? {
        try DopePersistenceEntityRecord
            .all()
            .withUuid(entityUuid)
            .select(DopePersistenceEntityRecord.Columns.baseComposableUuid, as: String.self)
            .fetchOne(db)
    }

    /// Returns up to five dot-paths of entities that compose the given entity.
    ///
    /// Bounded at 5 per the requireNoExternalReferrers convention.
    ///
    /// - Parameter entityUuid: The entity uuid to find composers for.
    /// - Returns: A list of dot-path references to composing entities.
    /// - Throws: Store errors if the query fails.
    private func baseComposableReferrers(
        entityUuid: String
    ) throws -> [String] {
        try DopeDomainChildPath.entities()
            .filter(DopePersistenceEntityRecord.Columns.baseComposableUuid == entityUuid)
            .limit(Self.referrerLimit)
            .fetchAll(db)
            .map(\.entityDotPath)
    }

    /// Referrer reports name a handful of offenders, never the whole set.
    private static let referrerLimit = 5

    /// Adds a new dope node to the tree and bumps the scope revision.
    ///
    /// - Parameter req: The add request with level, parent, fields, and metadata.
    /// - Returns: The response with the new node's uuid, version, and scope revision.
    /// - Throws: Store errors if validation fails or insert fails.
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
                detail: "'enums' is a reserved entity code (it disambiguates enum refs)"
            )
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
            sortOrder =
                try Table(spec.table)
                .filter(Column(parentColumn) == req.parentUuid)
                .select((max(Column("sort_order")) ?? -1) + 1, as: Int.self)
                .fetchOne(db) ?? 0
        }
        extra["sort_order"] = sortOrder

        try stageNodeAddLevelColumns(req, scope: scope, extra: &extra)

        let uuid = try core.insertBase(db, table: spec.table, extra: extra)
        let revision = try bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .persistence,
            ownerUuid: try owningPersistenceUuid(level: req.level, nodeUuid: uuid)
        )
        try recordDopeChange(
            scope: scope,
            action: "node_add",
            level: req.level,
            nodeUuid: uuid,
            revision: revision
        )
        return DopeNodeResponse(
            level: req.level,
            uuid: uuid,
            version: 0,
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    /// Validates and stages the level-specific columns of a node add.
    ///
    /// - Parameters:
    ///   - req: The add request.
    ///   - scope: The scope the new node belongs to.
    ///   - extra: The staging dictionary for inserted columns.
    /// - Throws: `StoreError.badRequest` if the entity or property shape is invalid.
    private func stageNodeAddLevelColumns(
        _ req: DopeNodeAddRequest,
        scope: DopeScopeRow,
        extra: inout [String: (any DatabaseValueConvertible)?]
    ) throws {
        switch req.level {
        case .entity:
            let entityType = req.fields.entityType ?? .model
            try validateEntityShape(
                scope: scope,
                entityUuid: nil,
                entityType: entityType,
                baseComposableUuid: req.fields.baseComposableUuid
            )
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
                scope: scope,
                propertyUuid: nil,
                entityUuid: req.parentUuid,
                dataType: dataType.rawValue,
                enumUuid: req.fields.enumUuid,
                relationshipTargetUuid: req.fields.relationshipTargetUuid,
                baseOriginPropertyUuid: req.fields.baseOriginPropertyUuid,
                autoIncrement: req.fields.autoIncrement,
                textCharLimit: req.fields.textCharLimit
            )
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
    }

    /// Updates a dope node with new field values and bumps the scope revision.
    ///
    /// - Parameter req: The update request with node uuid, level, expected version, and fields.
    /// - Returns: The response with the node's new version and scope revision.
    /// - Throws: Store errors if validation fails, version is stale, or update fails.
    func dopeNodeUpdate(_ req: DopeNodeUpdateRequest) throws -> DopeNodeResponse {
        let spec = DopeLevelSpec.spec(for: req.level)
        try validateNodeUpdateFields(req)

        let scope = try dopeOwningScope(level: req.level, nodeUuid: req.nodeUuid)

        var set = commonNodeUpdateColumns(req)

        if req.level == .entity {
            try applyEntityUpdate(req, scope: scope, spec: spec, set: &set)
        }
        if req.level == .property {
            try applyPropertyUpdate(req, scope: scope, spec: spec, set: &set)
        }

        guard !set.isEmpty else {
            throw StoreError.emptyUpdate(entity: spec.table)
        }
        try core.updateBase(
            db,
            table: spec.table,
            uuid: req.nodeUuid,
            expectedVersion: req.expectedVersion,
            set: set
        )
        let revision = try bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .persistence,
            ownerUuid: try owningPersistenceUuid(
                level: req.level,
                nodeUuid: req.nodeUuid
            )
        )
        try recordDopeChange(
            scope: scope,
            action: "node_update",
            level: req.level,
            nodeUuid: req.nodeUuid,
            revision: revision
        )
        guard
            let version =
                try Table(spec.table)
                .filter(Column("uuid") == req.nodeUuid)
                .select(Column("version"), as: Int64.self)
                .fetchOne(db)
        else {
            throw StoreError.corruptState(entity: spec.table, detail: "vanished after update")
        }
        return DopeNodeResponse(
            level: req.level,
            uuid: req.nodeUuid,
            version: version,
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    /// Validates an update's field ownership, code, and description before any read.
    ///
    /// - Parameter req: The update request.
    /// - Throws: `StoreError.badRequest` if a field is foreign to the level or malformed.
    private func validateNodeUpdateFields(_ req: DopeNodeUpdateRequest) throws {
        try requireOwnedFields(req.fields, level: req.level)
        if let code = req.fields.code {
            try DopeCode.validateCode(code, field: "\(req.level.rawValue) code")
            if req.level == .entity, code == DopeCode.reservedEnumSegment {
                throw StoreError.badRequest(
                    detail: "'enums' is a reserved entity code (it disambiguates enum refs)"
                )
            }
        }
        try validateDopeDescription(req.fields.description, level: req.level)
    }

    /// Stages the columns every level shares, plus entity type and representative file.
    ///
    /// - Parameter req: The update request.
    /// - Returns: The staged column updates.
    private func commonNodeUpdateColumns(
        _ req: DopeNodeUpdateRequest
    ) -> [String: (any DatabaseValueConvertible)?] {
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
        return set
    }

    /// Validates and stages the final entity type and base composable for an update.
    ///
    /// Either half can change in one call, and the second call of A.base=B /
    /// B.base=A must be the one that gets refused. Calls `validateEntityShape`
    /// and stages the update into the provided set.
    ///
    /// - Parameters:
    ///   - req: The update request containing field changes.
    ///   - scope: The scope the entity belongs to.
    ///   - spec: The level specification for the entity.
    ///   - set: The staging dictionary for column updates.
    /// - Throws: Store errors if validation fails.
    private func applyEntityUpdate(
        _ req: DopeNodeUpdateRequest,
        scope: DopeScopeRow,
        spec: DopeLevelSpec,
        set: inout [String: (any DatabaseValueConvertible)?]
    ) throws {
        guard let current = try DopePersistenceEntityRecord.all().withUuid(req.nodeUuid).fetchOne(db)
        else {
            throw StoreError.notFound(entity: spec.table, key: req.nodeUuid)
        }
        let finalType =
            req.fields.entityType
            ?? DopeEntityType(rawValue: current.entityType) ?? .model
        var finalBase = current.baseComposableUuid
        if let base = req.fields.baseComposableUuid { finalBase = base }
        if req.fields.clearBaseComposable == true { finalBase = nil }

        try validateEntityShape(
            scope: scope,
            entityUuid: req.nodeUuid,
            entityType: finalType,
            baseComposableUuid: finalBase
        )

        if req.fields.baseComposableUuid != nil || req.fields.clearBaseComposable == true {
            // updateValue, not subscript: assigning a typed nil to a
            // dictionary with Optional values REMOVES the key, and the
            // clear would silently vanish from the UPDATE.
            set.updateValue(finalBase, forKey: "base_composable_uuid")
        }
    }

    /// Validates and stages the final property shape for an update.
    ///
    /// Calls `validatePropertyShape` and stages the update into the provided set.
    /// Every clearable column goes through updateValue, not subscript: a typed-nil
    /// subscript assignment REMOVES the key, so a clear-alone call would throw
    /// emptyUpdate and a combined call would silently skip the clear.
    ///
    /// - Parameters:
    ///   - req: The update request containing field changes.
    ///   - scope: The scope the property belongs to.
    ///   - spec: The level specification for the property.
    ///   - set: The staging dictionary for column updates.
    /// - Throws: Store errors if validation fails.
    private func applyPropertyUpdate(
        _ req: DopeNodeUpdateRequest,
        scope: DopeScopeRow,
        spec: DopeLevelSpec,
        set: inout [String: (any DatabaseValueConvertible)?]
    ) throws {
        guard
            let current = try DopePersistenceEntityPropertyRecord.all().withUuid(req.nodeUuid).fetchOne(db)
        else {
            throw StoreError.notFound(entity: spec.table, key: req.nodeUuid)
        }
        let final = Self.finalPropertyShape(req, current: current)

        try validatePropertyShape(
            scope: scope,
            propertyUuid: req.nodeUuid,
            entityUuid: current.dopePersistenceEntityUuid,
            dataType: final.dataType,
            enumUuid: final.enumUuid,
            relationshipTargetUuid: final.relationshipTargetUuid,
            baseOriginPropertyUuid: final.baseOriginPropertyUuid,
            autoIncrement: final.autoIncrement,
            textCharLimit: final.textCharLimit
        )

        Self.stagePropertyUpdateColumns(req, final: final, set: &set)
    }

    /// A property's shape after an update's sets and clears are applied over its stored row.
    private struct PropertyFinalShape {
        var dataType: String
        var enumUuid: String?
        var relationshipTargetUuid: String?
        var autoIncrement: Bool?
        var textCharLimit: Int?
        var baseOriginPropertyUuid: String?
    }

    /// Applies an update's sets, then its clears, over the stored property row.
    ///
    /// - Parameters:
    ///   - req: The update request containing field changes.
    ///   - current: The stored property row.
    /// - Returns: The property's final shape.
    private static func finalPropertyShape(
        _ req: DopeNodeUpdateRequest,
        current: DopePersistenceEntityPropertyRecord
    ) -> PropertyFinalShape {
        var final = PropertyFinalShape(
            dataType: req.fields.dataType?.rawValue ?? current.dataType,
            enumUuid: current.dopePersistenceEnumUuid,
            relationshipTargetUuid: current.relationshipTargetUuid,
            autoIncrement: current.autoIncrement,
            textCharLimit: current.textCharLimit.map(Int.init),
            baseOriginPropertyUuid: current.baseOriginPropertyUuid
        )
        if let enumUuid = req.fields.enumUuid { final.enumUuid = enumUuid }
        if req.fields.clearEnum == true { final.enumUuid = nil }
        if let related = req.fields.relationshipTargetUuid { final.relationshipTargetUuid = related }
        if req.fields.clearRelationshipTarget == true { final.relationshipTargetUuid = nil }
        if let autoIncrement = req.fields.autoIncrement { final.autoIncrement = autoIncrement }
        if req.fields.clearAutoIncrement == true { final.autoIncrement = nil }
        if let limit = req.fields.textCharLimit { final.textCharLimit = limit }
        if req.fields.clearTextCharLimit == true { final.textCharLimit = nil }
        if let origin = req.fields.baseOriginPropertyUuid { final.baseOriginPropertyUuid = origin }
        if req.fields.clearBaseOrigin == true { final.baseOriginPropertyUuid = nil }
        return final
    }

    /// Stages the property columns an update sets or clears.
    ///
    /// - Parameters:
    ///   - req: The update request containing field changes.
    ///   - final: The validated final shape.
    ///   - set: The staging dictionary for column updates.
    private static func stagePropertyUpdateColumns(
        _ req: DopeNodeUpdateRequest,
        final: PropertyFinalShape,
        set: inout [String: (any DatabaseValueConvertible)?]
    ) {
        if let dataType = req.fields.dataType { set["data_type"] = dataType.rawValue }
        if let nullable = req.fields.nullable { set["nullable"] = nullable ? 1 : 0 }
        if let isUnique = req.fields.isUnique { set["is_unique"] = isUnique ? 1 : 0 }
        if req.fields.autoIncrement != nil || req.fields.clearAutoIncrement == true {
            set.updateValue(final.autoIncrement.map { $0 ? 1 : 0 }, forKey: "auto_increment")
        }
        if req.fields.textCharLimit != nil || req.fields.clearTextCharLimit == true {
            set.updateValue(final.textCharLimit, forKey: "text_char_limit")
        }
        if req.fields.enumUuid != nil || req.fields.clearEnum == true {
            set.updateValue(final.enumUuid, forKey: "dope_persistence_enum_uuid")
        }
        if req.fields.relationshipTargetUuid != nil || req.fields.clearRelationshipTarget == true {
            set.updateValue(final.relationshipTargetUuid, forKey: "relationship_target_uuid")
        }
        if req.fields.baseOriginPropertyUuid != nil || req.fields.clearBaseOrigin == true {
            set.updateValue(final.baseOriginPropertyUuid, forKey: "base_origin_property_uuid")
        }
    }

    /// Deletes a dope node, either soft-deleting or cascading as configured.
    ///
    /// Soft deletes are allowed only in overlay scopes; hard deletes check for
    /// external referrers before deleting and cascade in dependency order.
    ///
    /// - Parameter req: The delete request with node uuid, level, expected version, and soft flag.
    /// - Returns: The response with the deleted uuid, cascade counts, scope uuid, and revision.
    /// - Throws: Store errors if referrer checks fail, delete fails, or soft-delete rules violated.
    func dopeNodeDelete(_ req: DopeNodeDeleteRequest) throws -> DopeNodeDeleteResponse {
        guard req.level != .scope else {
            throw StoreError.badRequest(
                detail: "scope deletion is deferred to a later pass (it destroys the whole tree)"
            )
        }
        let spec = DopeLevelSpec.spec(for: req.level)
        let scope = try dopeOwningScope(level: req.level, nodeUuid: req.nodeUuid)

        // Soft delete is a stamp, not a removal. It deliberately skips
        // BOTH the referrer guard and the cascade: a tombstoned row is
        // still a row, so every RESTRICT FK pointing at it still resolves
        // and nothing below it needs to go. Reads do not filter it — that
        // is the point.
        if req.soft == true {
            return try dopeNodeSoftDelete(req, spec: spec, scope: scope)
        }

        try requireNoExternalReferrers(level: req.level, nodeUuid: req.nodeUuid)
        let cascaded = try dopeCascadeCounts(level: req.level, nodeUuid: req.nodeUuid)

        // Ordered deletes so a CASCADE can never race a RESTRICT: a
        // node's own relationship properties (referrers) go first, then
        // the remaining properties under it, then the guarded row.
        try deleteNodeDependents(level: req.level, nodeUuid: req.nodeUuid)
        try core.deleteBase(
            db,
            table: spec.table,
            uuid: req.nodeUuid,
            expectedVersion: req.expectedVersion
        )
        let revision = try bumpScopeRevision(scopeUuid: scope.uuid)
        try recordDopeChange(
            scope: scope,
            action: "node_delete",
            level: req.level,
            nodeUuid: req.nodeUuid,
            revision: revision
        )
        return DopeNodeDeleteResponse(
            deletedUuid: req.nodeUuid,
            cascaded: cascaded,
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    /// Stamps a node's deleted_on inside a masking scope and bumps the scope revision.
    ///
    /// - Parameters:
    ///   - req: The delete request.
    ///   - spec: The level specification for the node.
    ///   - scope: The scope the node belongs to.
    /// - Returns: The response with zero cascade counts and the new scope revision.
    /// - Throws: `StoreError.badRequest` in a base scope or on a tombstoned node.
    private func dopeNodeSoftDelete(
        _ req: DopeNodeDeleteRequest,
        spec: DopeLevelSpec,
        scope: DopeScopeRow
    ) throws -> DopeNodeDeleteResponse {
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
                    + "records real state only -- use a hard delete."
            )
        }
        let deletedOn: String? =
            try Table(spec.table)
            .filter(Column("uuid") == req.nodeUuid)
            .select(Column("deleted_on"), as: String?.self)
            .fetchOne(db) ?? nil
        guard deletedOn == nil else {
            throw StoreError.badRequest(
                detail: "node \(req.nodeUuid) is already soft-deleted"
            )
        }
        try core.updateBase(
            db,
            table: spec.table,
            uuid: req.nodeUuid,
            expectedVersion: req.expectedVersion,
            set: ["deleted_on": Store.isoNow()]
        )
        let revision = try bumpScopeRevision(
            scopeUuid: scope.uuid,
            area: .persistence,
            ownerUuid: try owningPersistenceUuid(
                level: req.level,
                nodeUuid: req.nodeUuid
            )
        )
        try recordDopeChange(
            scope: scope,
            action: "node_soft_delete",
            level: req.level,
            nodeUuid: req.nodeUuid,
            revision: revision
        )
        return DopeNodeDeleteResponse(
            deletedUuid: req.nodeUuid,
            cascaded: DopeTreeCounts(
                domains: 0,
                entities: 0,
                properties: 0,
                enums: 0,
                options: 0
            ),
            scopeUuid: scope.uuid,
            revision: revision
        )
    }

    /// Deletes a node's properties in RESTRICT-safe order before the node row itself.
    ///
    /// - Parameters:
    ///   - level: The level of the node being deleted.
    ///   - nodeUuid: The node uuid.
    /// - Throws: Store errors if a statement fails.
    private func deleteNodeDependents(level: DopeLevel, nodeUuid: String) throws {
        switch level {
        case .persistence:
            // Entities inside this domain may compose one another under
            // an ON DELETE RESTRICT self-FK; the CASCADE below would trip
            // it. External composers were already refused by the guard.
            try db.execute(
                sql: """
                    UPDATE dope_persistence_entity SET base_composable_uuid = NULL
                     WHERE dope_persistence_uuid = ? AND base_composable_uuid IS NOT NULL
                    """,
                arguments: [nodeUuid]
            )
            // Origin tags are data_type-independent — NULL them before
            // BOTH property DELETEs, or a tagged origin that is itself a
            // relationship property trips the RESTRICT mid-statement.
            try db.execute(
                sql: """
                    UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
                     WHERE base_origin_property_uuid IS NOT NULL
                       AND dope_persistence_entity_uuid IN (
                        SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                    """,
                arguments: [nodeUuid]
            )
            try db.execute(
                sql: """
                    DELETE FROM dope_persistence_entity_property
                     WHERE data_type = 'relationship'
                       AND dope_persistence_entity_uuid IN (
                        SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                    """,
                arguments: [nodeUuid]
            )
            try db.execute(
                sql: """
                    DELETE FROM dope_persistence_entity_property
                     WHERE dope_persistence_entity_uuid IN (
                        SELECT uuid FROM dope_persistence_entity WHERE dope_persistence_uuid = ?)
                    """,
                arguments: [nodeUuid]
            )
        case .entity:
            try deleteEntityDependents(nodeUuid: nodeUuid)
        default:
            break
        }
    }

    /// Deletes an entity's properties, relationship referrers first, before the entity row.
    ///
    /// - Parameter nodeUuid: The entity uuid.
    /// - Throws: Store errors if a statement fails.
    private func deleteEntityDependents(nodeUuid: String) throws {
        // Same relationship-first split as the domain case: a bulk
        // delete can scan a same-entity relationship TARGET before
        // its referencer and trip the RESTRICT FK mid-statement.
        try db.execute(
            sql: """
                UPDATE dope_persistence_entity_property SET base_origin_property_uuid = NULL
                 WHERE base_origin_property_uuid IS NOT NULL
                   AND dope_persistence_entity_uuid = ?
                """,
            arguments: [nodeUuid]
        )
        try db.execute(
            sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE data_type = 'relationship'
                   AND dope_persistence_entity_uuid = ?
                """,
            arguments: [nodeUuid]
        )
        try db.execute(
            sql: """
                DELETE FROM dope_persistence_entity_property
                 WHERE dope_persistence_entity_uuid = ?
                """,
            arguments: [nodeUuid]
        )
    }

    /// Validates that no external referrers exist before a hard delete.
    ///
    /// RESTRICT-friendly pre-checks that name the referring dot-paths instead of
    /// surfacing an opaque FK error. "External" means outside the subtree being
    /// deleted — internal referrers are handled by the ordered deletes.
    ///
    /// - Parameters:
    ///   - level: The level of the node being deleted.
    ///   - nodeUuid: The node uuid to check.
    /// - Throws: `StoreError.badRequest` if external referrers exist.
    private func requireNoExternalReferrers(
        level: DopeLevel,
        nodeUuid: String
    ) throws {
        // A list, not one request: the base-composable referrer queries read
        // FROM dope_persistence_entity while the property-ref queries read
        // FROM dope_persistence_entity_property, so they cannot share a
        // predicate.
        let properties = DopeDomainGrandchildPath.self
        let entities = DopeDomainChildPath.self
        let propertyColumns = DopePersistenceEntityPropertyRecord.Columns.self
        var referrers: [String] = []
        switch level {
        case .enumeration:
            referrers += try propertyPaths(
                properties.properties()
                    .filter(propertyColumns.dopePersistenceEnumUuid == nodeUuid)
            )
        case .property:
            referrers += try propertyPaths(
                properties.properties()
                    .filter(propertyColumns.relationshipTargetUuid == nodeUuid)
            )
            referrers += try propertyPaths(
                properties.properties()
                    .filter(propertyColumns.baseOriginPropertyUuid == nodeUuid)
            )
        case .entity:
            referrers += try propertyPaths(
                properties.propertiesReaching(
                    entityUuid: nodeUuid,
                    through: DopePersistenceEntityPropertyRecord.relationshipTarget
                )
            )
            referrers += try entityPaths(
                entities.entities()
                    .filter(DopePersistenceEntityRecord.Columns.baseComposableUuid == nodeUuid)
            )
            referrers += try propertyPaths(
                properties.propertiesReaching(
                    entityUuid: nodeUuid,
                    through: DopePersistenceEntityPropertyRecord.baseOriginProperty
                )
            )
        case .persistence:
            referrers += try propertyPaths(
                properties.propertiesReachingInto(persistenceUuid: nodeUuid)
            )
            referrers += try entityPaths(
                entities.entitiesComposingInside(persistenceUuid: nodeUuid)
            )
            referrers += try propertyPaths(
                properties.propertiesOriginatingInside(persistenceUuid: nodeUuid)
            )
        case .scope, .option:
            return
        }
        guard referrers.isEmpty else {
            throw StoreError.badRequest(
                detail:
                    "cannot delete: still referenced by " + referrers.joined(separator: ", ")
            )
        }
    }

    /// Fetches property referrer dot-paths up to the limit.
    ///
    /// Bound the result at the statement level rather than with `fetchAll().prefix`,
    /// to avoid fetching more rows than needed.
    ///
    /// - Parameter request: A query for domain grandchild paths.
    /// - Returns: A list of property dot-paths, bounded by `referrerLimit`.
    /// - Throws: Store errors if the query fails.
    private func propertyPaths(
        _ request: QueryInterfaceRequest<DopeDomainGrandchildPath>
    ) throws -> [String] {
        try request.limit(Self.referrerLimit).fetchAll(db).map(\.propertyDotPath)
    }

    /// Fetches entity referrer dot-paths up to the limit.
    ///
    /// - Parameter request: A query for domain child paths.
    /// - Returns: A list of entity dot-paths, bounded by `referrerLimit`.
    /// - Throws: Store errors if the query fails.
    private func entityPaths(
        _ request: QueryInterfaceRequest<DopeDomainChildPath>
    ) throws -> [String] {
        try request.limit(Self.referrerLimit).fetchAll(db).map(\.entityDotPath)
    }

    /// Counts the rows that would be cascaded when deleting a node.
    ///
    /// - Parameters:
    ///   - level: The level of the node being deleted.
    ///   - nodeUuid: The node uuid to count cascades for.
    /// - Returns: Counts of domains, entities, properties, enums, and options.
    /// - Throws: Store errors if the queries fail.
    private func dopeCascadeCounts(
        level: DopeLevel,
        nodeUuid: String
    ) throws -> DopeTreeCounts {
        switch level {
        case .persistence:
            let counts = try DopePersistenceCascadeCounts.request(persistenceUuid: nodeUuid)
                .fetchOne(db)
            return DopeTreeCounts(
                domains: 1,
                entities: counts?.entityCount ?? 0,
                properties: counts?.propertyCount ?? 0,
                enums: counts?.enumCount ?? 0,
                options: counts?.optionCount ?? 0
            )
        case .entity:
            let properties =
                try DopePersistenceEntityPropertyRecord
                .filter(
                    DopePersistenceEntityPropertyRecord.Columns.dopePersistenceEntityUuid
                        == nodeUuid
                )
                .fetchCount(db)
            return DopeTreeCounts(
                domains: 0,
                entities: 1,
                properties: properties,
                enums: 0,
                options: 0
            )
        case .enumeration:
            let options =
                try DopePersistenceEnumOptionRecord
                .filter(
                    DopePersistenceEnumOptionRecord.Columns.dopePersistenceEnumUuid == nodeUuid
                )
                .fetchCount(db)
            return DopeTreeCounts(
                domains: 0,
                entities: 0,
                properties: 0,
                enums: 1,
                options: options
            )
        case .property:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 1, enums: 0, options: 0)
        case .option:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 0, enums: 0, options: 1)
        case .scope:
            return DopeTreeCounts(domains: 0, entities: 0, properties: 0, enums: 0, options: 0)
        }
    }
}
