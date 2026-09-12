import Foundation
import GRDB

// VOCABULARY: "Repo" in this file means the USER'S GIT REPO (the {instance_root}/.gmcc tree),
// NOT the repository pattern — data access lives in DopeRepository. Filesystem work never
// enters a db transaction (the four-phase contract below).

/// The three whole-tree repo verbs, each a four-phase orchestration:
///
///   1. `dbQueue.read`  — resolve scope, instance root, tree, revision;
///   2. pure            — projection + validation, no db, no fs;
///   3. filesystem      — sandbox read or atomic write, NO db lock held
///                        (Server's serial dispatch queue means no other
///                        client's commit can interleave with phase 3);
///   4. `dbQueue.write` — ingest's tree replace, or the audit event alone.
///
/// Filesystem work never enters a db transaction — the Store+Backup /
/// digestKbite rule, load-bearing here because these verbs write into a
/// user's repo.
extension Store {

    /// The repo verbs are SESSION-BASE ONLY.
    ///
    /// `requireSessionUuid()` is not the gate it looks like: it succeeds for
    /// BOTH `.sessionInstance` and `.sessionInstanceItem`, because
    /// `isSessionOwned` covers the overlay tier too. Without this guard,
    /// a DOPE_WRITE_REPO aimed at a PROMPT scope resolves the same
    /// instance root a session-base write resolves and overwrites the shared
    /// {instance_root}/.gmcc tree — and an overlay carries soft-delete
    /// tombstones, which must never reach a committed .doped.json.
    ///
    /// Stated once here rather than three times inline, so the three verbs
    /// cannot drift apart.
    static func requireRepoWritableScope(_ scope: DopeScopeRow, verb: String) throws {
        guard scope.tier == .sessionInstance else {
            throw StoreError.dopeScopeNotRepoWritable(
                scopeUuid: scope.uuid, scopeType: scope.scopeType, verb: verb)
        }
    }

    // MARK: - read-repo

    public func dopeReadRepo(_ req: DopeReadRepoRequest) throws -> DopeReadRepoResponse {
        // Phase 1 — resolve the root (and the db revision when a scope is
        // named).
        let root: String
        var dbRevision: Int64?
        switch (req.scopeUuid, req.dirPath) {
        case (let scopeUuid?, nil):
            (root, dbRevision) = try dbQueue.read { db in
                guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                    throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
                }
                try Store.requireRepoWritableScope(scope, verb: "read-repo")
                return (try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid()),
                        scope.revision)
            }
        case (nil, let dirPath?):
            root = dirPath
        default:
            throw StoreError.badRequest(
                detail: "read-repo needs exactly one of --scope-uuid or --dir-path")
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
            warnings: repo.warnings)
    }

    // MARK: - write-repo

    public func dopeWriteRepo(_ req: DopeWriteRepoRequest) throws -> DopeWriteRepoResponse {
        // Phase 1 — scope + root + full tree.
        let (scope, root, tree, cogs) = try dbQueue.read {
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
                    scopeUuid: scope.uuid, expected: onDisk, actual: scope.revision)
            }
            result = try sandbox.writeAtomically(bundle)
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        // Phase 4 — audit event only; write-repo is a projection and does
        // NOT bump revision (that is what makes a repeat run idempotent).
        try dbQueue.write { db in
            var payload: [String: Any] = [
                "action": "write_repo",
                "scope_uuid": scope.uuid,
                "session_uuid": try scope.requireSessionUuid(),
                "revision": Int(scope.revision),
                "files_written": result.written,
            ]
            if req.force == true { payload["forced"] = true }
            if !result.pruned.isEmpty { payload["files_pruned"] = result.pruned }
            try self.appendEvent(db, kind: .dopeChange, subjectUuid: scope.uuid,
                                 payload: Store.jsonPayload(payload))
            try self.touchSession(db, uuid: try scope.requireSessionUuid())
        }
        return DopeWriteRepoResponse(
            dopeRoot: sandbox.dopeRoot.path,
            filesWritten: result.written,
            filesPruned: result.pruned,
            revision: scope.revision)
    }

    // MARK: - ingest

    public func dopeIngest(_ req: DopeIngestRequest) throws -> DopeIngestResponse {
        // Phase 1 — scope + root.
        let (scopeBefore, ownRoot) = try dbQueue.read { db -> (DopeScopeRow, String) in
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

        // Phase 4 — one transaction: gate revision == file.version - 1
        // exactly (single guarded UPDATE, changesCount-discriminated per the
        // updateBase idiom), ordered wipe, dependency-ordered re-insert.
        // Every child uuid changes — the locked no-smart-diff consequence.
        //
        // The file is the whole truth, so scope.doped.json's scope
        // name/description are APPLIED to the row (a hand-edit must never be
        // silently reverted by the next write-repo). The row's optimistic
        // lock `version` bumps ONLY when those fields actually change — SET
        // right-hand sides read the OLD row in SQLite — so a pure tree
        // ingest leaves it alone, per bumpScopeRevision's split-counter
        // invariant. The scope CODE is identity, never ingested.
        guard bundle.main.scope.code == scopeBefore.code else {
            throw StoreError.badRequest(detail:
                "\(DopeDocumentCodec.scopeFileName) names scope code '\(bundle.main.scope.code)' but the target scope is '\(scopeBefore.code)' — the code is identity and cannot be changed by ingest")
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
                throw StoreError.badRequest(detail:
                    "adopt requires the on-disk version (\(incoming)) to be strictly ahead of db revision \(scopeBefore.revision) — ingest never moves backward; publish db edits with dope write-repo instead")
            }
        }
        let expectedRevision = adopt ? scopeBefore.revision : incoming - 1
        return try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE dope_scope
                   SET revision = ?,
                       name = ?,
                       description = ?,
                       version = version + (CASE WHEN name IS NOT ? OR description IS NOT ?
                                                 THEN 1 ELSE 0 END),
                       updated_at = ?
                 WHERE uuid = ? AND revision = ?
                """, arguments: [
                    incoming,
                    bundle.main.scope.name, bundle.main.scope.description,
                    bundle.main.scope.name, bundle.main.scope.description,
                    Store.isoNow(), req.scopeUuid, expectedRevision,
                ])
            if db.changesCount == 0 {
                guard let actual = try Int64.fetchOne(
                    db, sql: "SELECT revision FROM dope_scope WHERE uuid = ?",
                    arguments: [req.scopeUuid]
                ) else {
                    throw StoreError.notFound(entity: "dope_scope", key: req.scopeUuid)
                }
                throw StoreError.revisionConflict(
                    scopeUuid: req.scopeUuid, expected: expectedRevision, actual: actual)
            }

            try self.wipeDopeTree(db, scopeUuid: req.scopeUuid)
            let counts = try self.insertDopeTree(
                db, scopeUuid: req.scopeUuid, domainFiles: bundle.domainFiles)
            try self.insertDopeCogs(
                db, scopeUuid: req.scopeUuid, cogFiles: bundle.cogFiles)
            // This tree just came FROM the files, so it IS the new merge
            // base: record every element's hash and clear the dirty flags.
            try self.stampProvenanceFromFiles(
                db, scopeUuid: req.scopeUuid, bundle: bundle)

            guard let scope = try self.fetchDopeScope(db, uuid: req.scopeUuid) else {
                throw StoreError.corruptState(entity: "dope_scope", detail: "vanished during ingest")
            }
            let gap = adopt ? (incoming - scopeBefore.revision - 1) : 0
            try self.recordDopeIngestEvent(db, scope: scope, before: scopeBefore.revision,
                                           counts: counts, adopted: adopt)
            return DopeIngestResponse(
                scope: scope, counts: counts,
                previousRevision: scopeBefore.revision,
                gapCrossed: gap > 0 ? gap : nil)
        }
    }

    private func recordDopeIngestEvent(
        _ db: Database, scope: DopeScopeRow, before: Int64, counts: DopeTreeCounts,
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
        try appendEvent(db, kind: .dopeChange, subjectUuid: scope.uuid,
                        payload: Store.jsonPayload(payload))
        try touchSession(db, uuid: scope.requireSessionUuid())
    }
}
