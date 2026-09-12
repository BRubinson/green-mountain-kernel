import Foundation

/// Files → db boot reconciliation for a session's SESSION_INSTANCE dope scope.
///
/// The repo's `.gmcc` dope tree travels with the branch, but a fresh checkout
/// mints a virgin scope (revision 0, empty tree) — so without this, every new
/// branch starts with an empty session dope. On the boot path the FILES are
/// authoritative forward: a virgin scope seeds wholesale, a scope behind the
/// files re-adopts. The db is never authoritative here; a db ahead of the
/// files means unpublished edits and only ever warns.
///
/// Direction is structural, not disciplinary: this type composes
/// DOPE_READ_REPO / DOPE_LIST / DOPE_INIT / DOPE_INGEST(adopt) and has no
/// path to DOPE_WRITE_REPO. Repo files are read, never written.
///
/// Every outcome is non-throwing — boot must never block on a domain model.
public enum DopeBootSync {
    public enum Outcome {
        /// No `.gmcc/scope.doped.json` on disk — the silent common case,
        /// decided by one stat before any socket is opened.
        case noRepoTree
        /// A RETIRED `.gmcc/dope` tree is present but the current layout is
        /// not. Distinct from `noRepoTree` on purpose: this outcome exists
        /// because the honest failure of moving the path constants is that
        /// every checkout still holding an old-shape tree would otherwise
        /// stat as "no dope here" and degrade silently to empty. Loud, and
        /// still non-throwing.
        case legacyLayout(path: String)
        case inSync(code: String, revision: Int64)
        case seeded(code: String, revision: Int64, counts: DopeTreeCounts)
        case readopted(code: String, from: Int64, to: Int64, counts: DopeTreeCounts)
        /// On-disk version is BEHIND the db — unpublished session edits.
        /// Warn only; never write files, never move revision backward.
        case filesBehind(code: String, dbRevision: Int64, diskVersion: Int64)
        /// Parse/validation/daemon failure — a warning, never a blocked boot.
        case unreadable(String)
    }

    /// Reconcile the session's SESSION_INSTANCE scope with the repo tree.
    /// `instanceRoot` is the repo checkout root (the tree lives at
    /// `{instanceRoot}/.gmcc`).
    public static func run(
        client: DaemonClient, sessionUuid: String, instanceRoot: String
    ) -> Outcome {
        let root = URL(fileURLWithPath: instanceRoot, isDirectory: true)
        let main = root.appendingPathComponent(
            ".gmcc/\(DopeDocumentCodec.scopeFileName)")
        guard FileManager.default.fileExists(atPath: main.path) else {
            // Before concluding "no dope", check for the retired layout —
            // otherwise a stale checkout is indistinguishable from a repo
            // that was never doped.
            let legacy = root.appendingPathComponent(
                ".gmcc/\(DopeDocumentCodec.legacyDopeDirectoryName)/\(DopeDocumentCodec.legacyMainFileName)")
            if FileManager.default.fileExists(atPath: legacy.path) {
                return .legacyLayout(path: legacy.path)
            }
            return .noRepoTree
        }
        do {
            let repo = try client.dopeReadRepo(DopeReadRepoRequest(dirPath: instanceRoot))
            let code = repo.bundle.main.scope.code
            let disk = repo.onDiskRevision

            let scopes = try client.dopeList(DopeListRequest(sessionUuid: sessionUuid)).scopes
            let existing = scopes.first { $0.code == code }

            let scopeUuid: String
            let dbRevision: Int64
            let minted: Bool
            if let existing {
                scopeUuid = existing.uuid
                dbRevision = existing.revision
                minted = false
            } else {
                // The scope identity comes from scope.doped.json — the code IS
                // identity to ingest; minting any other code guarantees a
                // refusal on the next step.
                let created = try client.dopeInit(DopeInitRequest(
                    sessionUuid: sessionUuid,
                    code: code,
                    name: repo.bundle.main.scope.name,
                    description: repo.bundle.main.scope.description))
                scopeUuid = created.scope.uuid
                dbRevision = created.scope.revision
                minted = true
            }

            if disk == dbRevision { return .inSync(code: code, revision: dbRevision) }
            if disk < dbRevision {
                return .filesBehind(code: code, dbRevision: dbRevision, diskVersion: disk)
            }
            let res = try client.dopeIngest(DopeIngestRequest(
                scopeUuid: scopeUuid, dirPath: nil, adopt: true))
            if minted || dbRevision == 0 {
                return .seeded(code: code, revision: res.scope.revision, counts: res.counts)
            }
            return .readopted(code: code, from: dbRevision, to: res.scope.revision,
                              counts: res.counts)
        } catch {
            return .unreadable(String(describing: error))
        }
    }

    /// One human line for hook/CLI output; nil for the silent outcomes.
    public static func notice(for outcome: Outcome) -> String? {
        switch outcome {
        case .noRepoTree, .inSync:
            return nil
        case let .seeded(code, revision, counts):
            return "[GMB] dope: seeded session scope '\(code)' from .gmcc at revision \(revision) "
                + "(\(counts.domains) domains, \(counts.entities) entities)"
        case let .readopted(code, from, to, _):
            return "[GMB] dope: re-ingested '\(code)' from .gmcc at revision \(to) (was \(from))"
        case let .filesBehind(code, dbRevision, diskVersion):
            return "[GMB] dope: WARN — session scope '\(code)' (revision \(dbRevision)) is AHEAD of "
                + ".gmcc (version \(diskVersion)); boot never writes files. "
                + "Publish with: gmcc_hook call DOPE_WRITE_REPO --json '{\"scope_uuid\":\"<uuid>\"}'"
        case let .legacyLayout(path):
            return "[GMB] dope: WARN — found a RETIRED .gmcc/dope tree at \(path) and no "
                + ".gmcc/\(DopeDocumentCodec.scopeFileName). The session scope was NOT seeded from it. "
                + "Republish with: gmcc_hook call DOPE_WRITE_REPO --json "
                + "'{\"scope_uuid\":\"<uuid>\",\"force\":true}', then: git rm -r .gmcc/dope"
        case let .unreadable(reason):
            return "[GMB] dope: WARN — sync skipped: \(reason) "
                + "(inspect with: gmcc_hook context ensure)"
        }
    }
}
