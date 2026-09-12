import Foundation
import GRDB

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
        let home = NSHomeDirectory()
        return PathsGetResponse(
            gmccRoot: Paths.root.path,
            dbPath: Paths.db.path,
            socketPath: Paths.socket.path,
            backupsRoot: Paths.backups.path,
            ckfsRoot: value(.ckfsRoot, fallback: "\(home)/gmcc_ckfs"),
            kbiteRoot: value(.kbiteRoot, fallback: "\(home)/gmcc_ckfs/kbites"),
            kbiteOpenRoot: value(.kbiteOpenRoot, fallback: "\(home)/gmcc_ckfs/kbites/open"),
            kbiteDigestedRoot: value(.kbiteDigestedRoot, fallback: "\(home)/gmcc_ckfs/kbites/digested")
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

    /// MemoryWatcher's reverse lookup: prompt by its ckfs folder path.
    func promptUuid(byStoragePath path: String) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT uuid FROM prompt WHERE ckfs_relative_storage_path = ?",
            arguments: [path])
    }
}
