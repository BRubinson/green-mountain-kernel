import Foundation
import GRDB

/// Reads and writes `dope_element_provenance` — the merge base.
///
/// Two writers, and they are deliberately the only two:
///   * `stampProvenanceFromFiles` runs after a files -> db sync and records
///     what each element looked like when it arrived, clearing the dirty
///     flag. This IS the base.
///   * `markLocallyModified` runs on a granular dope mutation and sets the
///     dirty flag for the affected dot-path.
///
/// Everything is addressed by dot-path, never uuid: ingest re-mints every
/// child uuid, so uuid-keyed provenance would be erased by the operation it
/// exists to inform.
extension Store {

    // MARK: - Cross-domain helper forwards (bodies in DopeProvenanceRepository)

    func dopeProvenance(_ db: Database, scopeUuid: String) throws -> [String: DopeMerge.Base] {
        try DopeProvenanceRepository(db: db, core: core).provenance(scopeUuid: scopeUuid)
    }

    func stampProvenanceFromFiles(
        _ db: Database, scopeUuid: String, bundle: DopeDocumentBundle
    ) throws {
        try DopeProvenanceRepository(db: db, core: core)
            .stampFromFiles(scopeUuid: scopeUuid, bundle: bundle)
    }

    func markLocallyModified(
        _ db: Database, scopeUuid: String, dotPath: String, kind: String
    ) throws {
        try DopeProvenanceRepository(db: db, core: core)
            .markLocallyModified(scopeUuid: scopeUuid, dotPath: dotPath, kind: kind)
    }

    func dopeDotPath(_ db: Database, nodeUuid: String, level: DopeLevel) throws -> String? {
        try DopeProvenanceRepository(db: db, core: core)
            .dotPath(nodeUuid: nodeUuid, level: level)
    }

    /// The dot-paths this session has edited, in order.
    func locallyModifiedPaths(_ db: Database, scopeUuid: String) throws -> [String] {
        try DopeProvenanceRepository(db: db, core: core)
            .locallyModifiedPaths(scopeUuid: scopeUuid)
    }
}

// MARK: - Merge planning and resolution

extension Store {

    /// The current merge plan for a scope: db tree vs the on-disk tree,
    /// judged against the stored base.
    ///
    /// Read-only and non-blocking by construction — it never ingests, never
    /// writes files, and never mutates provenance. Boot sync calls it to
    /// report rather than to decide, which is what keeps the documented
    /// "boot must never block on a domain model" contract true.
    public func dopeMergePlan(scopeUuid: String) throws -> [DopeMerge.Outcome] {
        let (scope, root) = try dbQueue.read { db -> (DopeScopeRow, String) in
            guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
            }
            try Store.requireRepoWritableScope(scope, verb: "merge")
            return (scope, try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid()))
        }

        let theirs: [DopeMerge.Element]
        do {
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            theirs = DopeMerge.elements(of: try sandbox.readBundle().bundle)
        } catch let error as DopeRepoSandbox.SandboxError {
            throw StoreError.badRequest(detail: error.description)
        }

        return try dbQueue.read { db in
            let tree = try self.fetchDopeTree(db, scope: scope, forProjection: true)
            let ours = DopeMerge.elements(of: DopeProjection.documents(from: tree))
            let base = try self.dopeProvenance(db, scopeUuid: scopeUuid)
            return DopeMerge.plan(ours: ours, theirs: theirs, base: base)
        }
    }

    /// Resolve one conflicting dot-path — or every one of them.
    ///
    /// Resolution is expressed IN the base rather than by rewriting a tree,
    /// which is what makes it a single small write instead of a second merge
    /// engine:
    ///
    ///   take theirs → clear the dirty flag, so the next sync takes the file
    ///                 exactly as an untouched element would;
    ///   take ours   → re-base onto the file's CURRENT hash while staying
    ///                 dirty, so the local edit is kept and the file is no
    ///                 longer considered to have moved.
    ///
    /// Either way the conflict is gone on the next plan, in the direction
    /// that was chosen.
    @discardableResult
    public func dopeResolve(
        scopeUuid: String, dotPath: String?, takeOurs: Bool
    ) throws -> [String] {
        let plan = try dopeMergePlan(scopeUuid: scopeUuid)
        let conflicts = DopeMerge.conflicts(in: plan)

        let targets: [DopeMerge.Outcome]
        if let dotPath {
            guard let match = conflicts.first(where: { $0.dotPath == dotPath }) else {
                throw StoreError.badRequest(
                    detail: conflicts.isEmpty
                        ? "no unresolved dope conflicts in scope \(scopeUuid)"
                        : "'\(dotPath)' is not a conflicting path; conflicts: "
                          + conflicts.map(\.dotPath).joined(separator: ", "))
            }
            targets = [match]
        } else {
            targets = conflicts
        }
        guard !targets.isEmpty else { return [] }

        // The file side's current hashes — what "ours wins" must re-base onto.
        let theirHashes = try dbQueue.read { db -> [String: String] in
            guard let scope = try self.fetchDopeScope(db, uuid: scopeUuid) else {
                throw StoreError.notFound(entity: "dope_scope", key: scopeUuid)
            }
            let root = try self.instanceRoot(db, sessionUuid: try scope.requireSessionUuid())
            let sandbox = try DopeRepoSandbox.resolve(instanceRoot: root)
            var out = [String: String]()
            for element in DopeMerge.elements(of: try sandbox.readBundle().bundle) {
                out[element.dotPath] = element.contentHash
            }
            return out
        }

        try dbQueue.write { db in
            let now = Store.isoNow()
            for target in targets {
                if takeOurs {
                    try db.execute(sql: """
                        UPDATE dope_element_provenance
                           SET synced_content_hash = ?, locally_modified = 1, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """, arguments: [theirHashes[target.dotPath], now,
                                         scopeUuid, target.dotPath])
                } else {
                    try db.execute(sql: """
                        UPDATE dope_element_provenance
                           SET locally_modified = 0, updated_at = ?
                         WHERE dope_scope_uuid = ? AND dot_path = ?
                        """, arguments: [now, scopeUuid, target.dotPath])
                }
            }
        }
        return targets.map(\.dotPath)
    }
}
