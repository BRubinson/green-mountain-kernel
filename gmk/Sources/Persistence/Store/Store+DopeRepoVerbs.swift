import Foundation
import GRDB

// VOCABULARY: "Repo" in this file means the USER'S GIT REPO (the {instance_root}/.gmcc tree),
// NOT the repository pattern — data access lives in DopeRepository. Filesystem work never
// enters a db transaction (the four-phase contract below).

/// The three whole-tree repo verbs, each a four-phase orchestration: db read to
/// resolve scope, instance root, tree and revision; a pure projection and
/// validation step; contained filesystem work with NO db lock held, safe because
/// Server's serial dispatch queue keeps another client's commit from
/// interleaving; then the db write.
/// Phase 3 is why these verbs REFUSE to run inside a caller-opened transaction
/// (`StoreError.notComposable`): composing one would hold the single writer
/// across filesystem I/O, blocking every other writer on someone else's disk.
extension Store {

    /// Validates that a scope is writable at the repo level.
    ///
    /// The repo verbs are SESSION-BASE ONLY. `requireSessionUuid()` is not the gate
    /// it looks like: it succeeds for BOTH `.sessionInstance` and `.sessionInstanceItem`,
    /// because `isSessionOwned` covers the overlay tier. Without this guard a
    /// DOPE_WRITE_REPO aimed at a PROMPT scope resolves the same instance root a
    /// session-base write does and overwrites the shared {instance_root}/.gmcc tree —
    /// and an overlay carries tombstones, which must never reach a committed .doped.json.
    ///
    /// - Parameters:
    ///   - scope: The dope scope row.
    ///   - verb: The repo verb name for error reporting.
    /// - Throws: `StoreError.dopeScopeNotRepoWritable` if the scope is not writable.
    static func requireRepoWritableScope(_ scope: DopeScopeRow, verb: String) throws {
        guard scope.tier == .sessionInstance else {
            throw StoreError.dopeScopeNotRepoWritable(
                scopeUuid: scope.uuid,
                scopeType: scope.scopeType,
                verb: verb
            )
        }
    }

    // MARK: - read-repo

    /// Reads and validates the dope tree from the filesystem.
    ///
    /// A four-phase operation: scope resolution, parsing, validation, then response.
    /// Must not run inside a caller-opened transaction.
    ///
    /// - Parameter req: The read request with scope uuid or directory path.
    /// - Returns: The parsed and validated bundle with optional drift report.
    /// - Throws: `StoreError` for malformed requests or validation failures.
    func dopeReadRepo(_ req: DopeReadRepoRequest) throws -> DopeReadRepoResponse {
        // FOUR-PHASE VERB — must not run inside a caller-opened transaction.
        // Phase 3 does filesystem work while holding NO db lock, by design.
        // Composing this would pin the single writer across file I/O and block
        // every other writer in the machine, hooks included, on someone else's
        // disk. Refusing loudly in five places beats maintaining a list of
        // which of ~230 verbs are composable.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "dopeReadRepo")
        }
        // Phase 1 — resolve the root (and the db revision when a scope is
        // named).
        let root: String
        var dbRevision: Int64?
        switch (req.scopeUuid, req.dirPath) {
        case (let scopeUuid?, nil):
            (root, dbRevision) = try boundaryRead { db in
                guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                    throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
                }
                try Store.requireRepoWritableScope(scope, verb: "read-repo")
                return (
                    try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid()),
                    scope.revision
                )
            }
        case (nil, let dirPath?):
            root = dirPath
        default:
            throw StoreError.badRequest(
                detail: "read-repo needs exactly one of --scope-uuid or --dir-path"
            )
        }

        // Phase 3 — read (no phase-2 work on the way in; validation follows
        // the parse).
        let sandbox: DopeRepoSandbox
        let repo: DopeRepoSandbox.RepoBundle
        do {
            sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            repo = try sandbox.readBundle()
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        // Phase 2 (outbound) — validate; a broken tree is still returned to
        // the caller as data plus warnings? No: read-repo's contract is
        // parse + validate, so validation failures are loud.
        do {
            try DopeValidator.validate(repo.bundle)
        } catch let error as DopeValidator.BundleError {
            throw StoreError.badRequest(detail: error.description)
        }

        let onDisk = repo.bundle.main.version
        return DopeReadRepoResponse(
            bundle: repo.bundle,
            onDiskRevision: onDisk,
            dbRevision: dbRevision,
            drift: dbRevision.map { $0 != onDisk },
            warnings: repo.warnings
        )
    }

    // MARK: - write-repo

    /// Writes the in-memory dope tree to the filesystem atomically.
    ///
    /// A four-phase operation: scope and tree resolution, projection, atomic write,
    /// then audit event. Must not run inside a caller-opened transaction. Idempotent:
    /// repeating with the same tree does not bump revision.
    ///
    /// - Parameter req: The write request with scope uuid and optional force flag.
    /// - Returns: The written file paths and pruned paths.
    /// - Throws: `StoreError` for missing scopes, revision conflicts, or write failures.
    func dopeWriteRepo(_ req: DopeWriteRepoRequest) throws -> DopeWriteRepoResponse {
        // FOUR-PHASE VERB — must not run inside a caller-opened transaction.
        // Phase 3 does filesystem work while holding NO db lock, by design.
        // Composing this would pin the single writer across file I/O and block
        // every other writer in the machine, hooks included, on someone else's
        // disk. Refusing loudly in five places beats maintaining a list of
        // which of ~230 verbs are composable.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "dopeWriteRepo")
        }
        // Phase 1 — scope + root + full tree.
        let (scope, root, tree, cogs) = try boundaryRead {
            db -> (DopeScopeRow, String, DopeScopeTree, [DopeCogNode]) in
            guard let scope = try self.fetchDopeScope(db, uuid: req.scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
            }
            try Store.requireRepoWritableScope(scope, verb: "write-repo")
            let root = try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid())
            // forProjection: tombstones are overlay-tier personal state and
            // must never reach a committed .doped.json.
            let tree = try self.fetchDopeTree(db, scope: scope, forProjection: true)
            let cogs = try self.fetchDopeCogs(db, scopeUuid: req.scopeUuid)
            return (scope, root, tree, cogs)
        }

        // Phase 2 — project.
        let bundle = DopeProjection.documents(from: tree, cogs: cogs)

        // Phase 3 — gate + atomic write, no lock held.
        let sandbox: DopeRepoSandbox
        let result: DopeRepoSandbox.WriteResult
        do {
            sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            if let onDisk = sandbox.peekRevision(), onDisk > scope.revision, req.force != true {
                throw StoreError.revisionConflict(
                    scopeUuid: scope.uuid,
                    expected: onDisk,
                    actual: scope.revision
                )
            }
            result = try sandbox.writeAtomically(bundle)
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        // Phase 4 — audit event only; write-repo is a projection and does
        // NOT bump revision (that is what makes a repeat run idempotent).
        try boundary { db in
            var payload: [String: Any] = [
                "action": "write_repo",
                "scope_uuid": scope.uuid,
                "session_uuid": try scope.requireSessionUuid(),
                "revision": Int(scope.revision),
                "files_written": result.written,
            ]
            if req.force == true { payload["forced"] = true }
            if !result.pruned.isEmpty { payload["files_pruned"] = result.pruned }
            try self.appendEvent(
                db,
                kind: .dopeChange,
                subjectUuid: scope.uuid,
                payload: Store.jsonPayload(payload)
            )
            try self.touchSession(db, uuid: try scope.requireSessionUuid())
        }
        return DopeWriteRepoResponse(
            dopeRoot: sandbox.dopeRoot.path,
            filesWritten: result.written,
            filesPruned: result.pruned,
            revision: scope.revision
        )
    }

    // MARK: - ingest

    /// Ingests the dope tree from the filesystem into the database.
    ///
    /// A four-phase operation: scope resolution, file parsing, validation, then
    /// atomic database update. Must not run inside a caller-opened transaction. The
    /// tree becomes the new merge base with every element's hash stamped and dirty
    /// flags cleared. Uses either strict mode (incoming - 1) or adopt (observed revision).
    ///
    /// - Parameter req: The ingest request with scope uuid, optional directory, and adopt flag.
    /// - Returns: The updated scope, element counts, and optional revision gap crossed.
    /// - Throws: `StoreError` for validation failures, code mismatches, or revision conflicts.
    func dopeIngest(_ req: DopeIngestRequest) throws -> DopeIngestResponse {
        // FOUR-PHASE VERB — must not run inside a caller-opened transaction.
        // Phase 3 does filesystem work while holding NO db lock, by design.
        // Composing this would pin the single writer across file I/O and block
        // every other writer in the machine, hooks included, on someone else's
        // disk. Refusing loudly in five places beats maintaining a list of
        // which of ~230 verbs are composable.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "dopeIngest")
        }
        // Phase 1 — scope + root.
        let (scopeBefore, ownRoot) = try boundaryRead { db -> (DopeScopeRow, String) in
            guard let scope = try self.fetchDopeScope(db, uuid: req.scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
            }
            try Store.requireRepoWritableScope(scope, verb: "ingest")
            return (scope, try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid()))
        }

        // Phase 3 — read the files (before the write transaction opens).
        let bundle: DopeDocumentBundle
        do {
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: req.dirPath ?? ownRoot)
            bundle = try sandbox.readBundle().bundle
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        // Phase 2 — validate the whole tree before touching a row.
        do {
            try DopeValidator.validate(bundle)
        } catch let error as DopeValidator.BundleError {
            throw StoreError.badRequest(detail: error.description)
        }

        // Phase 4 — one transaction: gate revision == file.version - 1 exactly,
        // ordered wipe, dependency-ordered re-insert. Every child uuid changes,
        // which is the no-smart-diff consequence.
        // The file is the whole truth, so scope.doped.json's name and description
        // are APPLIED to the row, and a hand-edit must never be silently reverted
        // by the next write-repo. The row's optimistic lock `version` bumps ONLY
        // when those fields change, so a pure tree ingest leaves it alone. The
        // scope CODE is identity and is never ingested.
        guard bundle.main.scope.code == scopeBefore.code else {
            throw StoreError.badRequest(
                detail:
                    "\(DopeDocumentCodec.scopeFileName) names scope code '\(bundle.main.scope.code)' but the target scope is '\(scopeBefore.code)' — the code is identity and cannot be changed by ingest"
            )
        }
        // The gate is PARAMETERIZED, never weakened: the strict path binds
        // `incoming - 1` (the lost-update detector); adopt binds the OBSERVED
        // revision — the caller declared the files authoritative, but the
        // guarded WHERE still makes a concurrent writer lose the race cleanly.
        // Adopt keeps exactly one invariant: monotonicity. Backward is the
        // one genuinely destructive direction (a stale checkout clobbering
        // newer db work) and is refused outright.
        let incoming = bundle.main.version
        let adopt = req.adopt == true
        if adopt {
            guard incoming > scopeBefore.revision else {
                throw StoreError.badRequest(
                    detail:
                        "adopt requires the on-disk version (\(incoming)) to be strictly ahead of db revision \(scopeBefore.revision) — ingest never moves backward; publish db edits with dope write-repo instead"
                )
            }
        }
        let expectedRevision = adopt ? scopeBefore.revision : incoming - 1
        return try boundary { db in
            try DopeRepository(db: db, core: self.core)
                .applyIngestedScope(
                    scopeUuid: req.scopeUuid,
                    incoming: incoming,
                    expectedRevision: expectedRevision,
                    name: bundle.main.scope.name,
                    description: bundle.main.scope.description
                )

            try self.wipeDopeTree(db, scopeUuid: req.scopeUuid)
            let counts = try self.insertDopeTree(
                db,
                scopeUuid: req.scopeUuid,
                domainFiles: bundle.domainFiles
            )
            try self.insertDopeCogs(
                db,
                scopeUuid: req.scopeUuid,
                cogFiles: bundle.cogFiles
            )
            // This tree just came FROM the files, so it IS the new merge
            // base: record every element's hash and clear the dirty flags.
            try self.stampProvenanceFromFiles(
                db,
                scopeUuid: req.scopeUuid,
                bundle: bundle
            )

            guard let scope = try self.fetchDopeScope(db, uuid: req.scopeUuid) else {
                throw StoreError.corruptState(entity: "dope_scope", detail: "vanished during ingest")
            }
            let gap = adopt ? (incoming - scopeBefore.revision - 1) : 0
            try self.recordDopeIngestEvent(
                db,
                scope: scope,
                before: scopeBefore.revision,
                counts: counts,
                adopted: adopt
            )
            return DopeIngestResponse(
                scope: scope,
                counts: counts,
                previousRevision: scopeBefore.revision,
                gapCrossed: gap > 0 ? gap : nil
            )
        }
    }

    /// Records an audit event for a dope tree ingest operation.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - scope: The scope row after ingest.
    ///   - before: The scope's revision before ingest.
    ///   - counts: The element counts in the ingested tree.
    ///   - adopted: True if the ingest used adopt mode; false for strict mode.
    /// - Throws: Database errors.
    private func recordDopeIngestEvent(
        _ db: Database,
        scope: DopeScopeRow,
        before: Int64,
        counts: DopeTreeCounts,
        adopted: Bool
    ) throws {
        var payload: [String: Any] = [
            "action": adopted ? (before == 0 ? "boot_seed" : "boot_adopt") : "ingest",
            "scope_uuid": scope.uuid,
            "session_uuid": try scope.requireSessionUuid(),
            "revision": Int(scope.revision),
            "previous_revision": Int(before),
            "domains": counts.domains,
            "entities": counts.entities,
            "properties": counts.properties,
            "enums": counts.enums,
            "options": counts.options,
        ]
        if adopted { payload["adopted"] = true }
        try appendEvent(
            db,
            kind: .dopeChange,
            subjectUuid: scope.uuid,
            payload: Store.jsonPayload(payload)
        )
        try touchSession(db, uuid: scope.requireSessionUuid())
    }
}
