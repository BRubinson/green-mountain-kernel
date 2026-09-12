import CryptoKit
import Foundation
import GRDB

/// Shared instance-identity derivation: `{repo}_{first 4 hex of md5(abs path)}`.
/// The single Swift home of the convention gmcc_session_startup.sh mirrors in shell —
/// GitContext (the client side) and SandboxRetarget both call this so the hash can
/// never drift between the live and sandbox sides.
public enum InstanceIdentity {
    public static func code(repoName: String, absolutePath: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(absolutePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(repoName)_\(hex.prefix(4))"
    }
}

/// Offline retarget of a *sandbox copy* of gmcc.db, run BEFORE any sandbox
/// daemon ever boots. This closes the first-boot window where a freshly
/// spawned sandbox daemon would read copied `daemon_config` rows that still
/// point at the LIVE ckfs, and rehomes the instance identity (the code hashes
/// the absolute repo path, so an untouched copy would resolve to a fresh
/// empty instance).
///
/// This is the one sanctioned direct-db-file writer outside the daemon: it
/// only ever opens a quiesced staged copy, and it structurally refuses the
/// production database.
public struct SandboxRetarget {
    public struct Result: Sendable {
        public let oldInstanceCode: String
        public let newInstanceCode: String
        public let rewrittenTables: [String]
    }

    public enum RetargetError: Error, CustomStringConvertible {
        case refusedProdDb(String)
        case instanceNotFound(String)

        public var description: String {
            switch self {
            case .refusedProdDb(let p):
                return "refusing to retarget the production database at \(p)"
            case .instanceNotFound(let p):
                return "no instance row with absolute_file_system_path = \(p)"
            }
        }
    }

    /// The default production db location, computed WITHOUT the GMCC_ROOT
    /// override so a sandboxed process still knows where prod lives.
    static var prodDbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("gmcc", isDirectory: true)
            .appendingPathComponent("gmcc.db", isDirectory: false).path
    }

    /// Every base table carrying a `ckfs_relative_storage_path` column,
    /// discovered from the live schema (never a hardcoded list, so a future
    /// path-bearing migration is covered automatically). FTS shadow tables
    /// are excluded — external-content mirrors sync via triggers.
    static func storagePathTables(_ db: Database) throws -> [String] {
        let names = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table'
              AND sql NOT LIKE 'CREATE VIRTUAL%'
              AND name NOT LIKE '%_fts%'
              AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)
        var hits: [String] = []
        for table in names {
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            if cols.contains(where: { ($0["name"] as String?) == "ckfs_relative_storage_path" }) {
                hits.append(table)
            }
        }
        return hits
    }

    /// Rewrite `dbPath` (a staged sandbox copy) in one transaction:
    /// - daemon_config ckfs/kbite roots -> the sandbox paths
    /// - the instance row whose absolute_file_system_path == `oldRepoPath`
    ///   -> identity derived from `newRepoPath`
    /// - every ckfs_relative_storage_path: `instances/<old>` -> `instances/<new>`
    @discardableResult
    public static func run(
        dbPath: String,
        oldRepoPath: String,
        newRepoPath: String,
        ckfsRoot: String,
        kbiteRoot: String,
        kbiteOpenRoot: String,
        kbiteDigestedRoot: String
    ) throws -> Result {
        let canonicalTarget = URL(fileURLWithPath: dbPath).resolvingSymlinksInPath().path
        let canonicalProd = URL(fileURLWithPath: prodDbPath).resolvingSymlinksInPath().path
        guard canonicalTarget != canonicalProd else {
            throw RetargetError.refusedProdDb(dbPath)
        }

        // Canonicalize both repo paths: sessions inside the sandbox derive
        // the instance code from git's PHYSICAL path (rev-parse), so hashing
        // an unresolved symlinked path here would strand the whole copied
        // history behind a code mismatch.
        let oldRepoPath = URL(fileURLWithPath: oldRepoPath).resolvingSymlinksInPath().path
        let newRepoPath = URL(fileURLWithPath: newRepoPath).resolvingSymlinksInPath().path

        let queue = try DatabaseQueue(path: dbPath)
        defer { try? queue.close() }

        return try queue.write { db in
            // 1. Config roots — the copied rows still point at the live tree.
            let configPairs: [(ConfigKey, String)] = [
                (.ckfsRoot, ckfsRoot),
                (.kbiteRoot, kbiteRoot),
                (.kbiteOpenRoot, kbiteOpenRoot),
                (.kbiteDigestedRoot, kbiteDigestedRoot),
            ]
            for (key, value) in configPairs {
                try db.execute(
                    sql: """
                        UPDATE daemon_config
                        SET config_value = ?, version = version + 1, updated_at = ?
                        WHERE config_key = ?
                        """,
                    arguments: [value, Store.isoNow(), key.rawValue])
            }

            // 2. Instance identity.
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT uuid, code, name FROM instance WHERE absolute_file_system_path = ?",
                arguments: [oldRepoPath])
            else {
                throw RetargetError.instanceNotFound(oldRepoPath)
            }
            let instanceUuid: String = row["uuid"]
            let oldCode: String = row["code"]
            let repoName = URL(fileURLWithPath: newRepoPath).lastPathComponent
            let newCode = InstanceIdentity.code(repoName: repoName, absolutePath: newRepoPath)

            try db.execute(
                sql: """
                    UPDATE instance
                    SET code = ?, name = ?, absolute_file_system_path = ?,
                        version = version + 1, updated_at = ?
                    WHERE uuid = ?
                    """,
                arguments: [newCode, newCode, newRepoPath, Store.isoNow(), instanceUuid])

            // 3. Storage paths — exact-string guards only (no LIKE: `_` in
            //    every instance code is a LIKE wildcard), values bound rather
            //    than interpolated. Mid-path and end-of-path forms.
            let midOld = "instances/\(oldCode)/"
            let midNew = "instances/\(newCode)/"
            let sufOld = "instances/\(oldCode)"
            let sufNew = "instances/\(newCode)"
            let tables = try storagePathTables(db)
            for table in tables {
                try db.execute(
                    sql: """
                        UPDATE \(table)
                        SET ckfs_relative_storage_path =
                            replace(ckfs_relative_storage_path, ?, ?)
                        WHERE instr(ckfs_relative_storage_path, ?) > 0
                        """,
                    arguments: [midOld, midNew, midOld])
                try db.execute(
                    sql: """
                        UPDATE \(table)
                        SET ckfs_relative_storage_path =
                            substr(ckfs_relative_storage_path, 1,
                                   length(ckfs_relative_storage_path) - ?) || ?
                        WHERE substr(ckfs_relative_storage_path, -?) = ?
                        """,
                    arguments: [sufOld.count, sufNew, sufOld.count, sufOld])
            }

            return Result(
                oldInstanceCode: oldCode,
                newInstanceCode: newCode,
                rewrittenTables: tables)
        }
    }
}
