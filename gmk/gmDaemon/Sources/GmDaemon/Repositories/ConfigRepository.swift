import Foundation
import GRDB
import GmDaemonSdk

/// Data access for the daemon_config table (plus the MemoryWatcher's prompt
/// reverse lookup). Runs INSIDE a Store-owned transaction; holds no dbQueue
/// and never self-transacts.
struct ConfigRepository: RepositoryContext {
    let db: Database
    let core: StoreCore

    func pathsGet() throws -> PathsGetResponse {
        let config = try Dictionary(
            uniqueKeysWithValues: Row.fetchAll(
                db, sql: "SELECT config_key, config_value FROM daemon_config"
            ).map { ($0["config_key"] as String, $0["config_value"] as String) })
        func value(_ key: ConfigKey, fallback: String) -> String {
            config[key.rawValue] ?? fallback
        }

        // ONE root, and the DB's answer for it is the config row — which is
        // what makes GmEnvironment.check() an env-vs-DB comparison rather than
        // env-vs-this-process. Paths.root is the fallback, not the primary: a
        // database that has never had `gmfs_root` set is correctly described by
        // wherever the daemon serving it actually lives.
        //
        // THESE FALLBACKS ARE WHERE THE NEW DEFAULTS LIVE. The m0001 seed block
        // has shipped and must not be edited, so a database created before the
        // rename carries the RETIRED key, pointing at the retired layout, right
        // up until m0027 renames it. Everything below therefore has to work
        // with `gmfs_root` absent.
        let fsRoot = value(.gmFsRoot, fallback: Paths.root.path)
        // Derived from the RESOLVED root, not from a second $HOME literal, so
        // an overridden root (a sandbox) carries its whole subtree with it
        // instead of pointing the kbite roots back at the real home directory.
        let root = URL(fileURLWithPath: fsRoot, isDirectory: true)
        let kbites = root.appendingPathComponent("kbites", isDirectory: true)

        return PathsGetResponse(
            gmFsRoot: fsRoot,
            dbPath: Paths.db.path,
            socketPath: Paths.socket.path,
            backupsRoot: Paths.backups.path,
            projectsRoot: root.appendingPathComponent("projects", isDirectory: true).path,
            kbiteRoot: value(.kbiteRoot, fallback: kbites.path),
            kbiteOpenRoot: value(
                .kbiteOpenRoot,
                fallback: kbites.appendingPathComponent("open", isDirectory: true).path),
            kbiteDigestedRoot: value(
                .kbiteDigestedRoot,
                fallback: kbites.appendingPathComponent("digested", isDirectory: true).path)
        )
    }

    func configSet(_ req: ConfigSetRequest, value: String) throws -> ConfigSetResponse {
        // Upsert without version threading: config keys are singletons
        // owned by the daemon; last write wins (still audited via the
        // event trail).
        if try Row.fetchOne(
            db, sql: "SELECT 1 FROM daemon_config WHERE config_key = ?",
            arguments: [req.key.rawValue]
        ) != nil {
            try db.execute(
                sql: """
                    UPDATE daemon_config
                    SET config_value = ?, version = version + 1, updated_at = ?
                    WHERE config_key = ?
                    """,
                arguments: [value, Store.isoNow(), req.key.rawValue])
        } else {
            try core.insertBase(db, table: "daemon_config", extra: [
                "config_key": req.key.rawValue,
                "config_value": value,
            ])
        }
        try core.appendEvent(
            db, kind: .configSet,
            payload: Store.jsonPayload(["key": req.key.rawValue, "value": value]))
        return ConfigSetResponse(key: req.key, value: value)
    }

    func configValue(_ key: ConfigKey) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT config_value FROM daemon_config WHERE config_key = ?",
            arguments: [key.rawValue])
    }

    /// MemoryWatcher's reverse lookup: prompt by its gmfs folder path.
    func promptUuid(byStoragePath path: String) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE gmfs_relative_storage_path = ?",
            arguments: [path])
    }
}
