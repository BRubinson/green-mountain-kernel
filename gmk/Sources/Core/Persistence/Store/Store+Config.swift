import Foundation
import GRDB

// PATHS_GET / CONFIG_SET — the daemon's config subsystem. Backed by
// the daemon_config table (seeded with $HOME defaults by m0002) rather than
// env reads: the daemon's environment is a posix_spawn snapshot of whichever
// client invocation autostarted it, so $GMCC_* would be stale or absent. The key
// space is enum-bound (ConfigKey) — an unknown key is BAD_REQUEST. Retires
// GMVibes' ~/.zshrc scraping fallback.
//
// Bodies live in ConfigRepository; these wrappers own the transaction.

extension Store {
    /// Fetches the daemon's paths configuration.
    /// - Returns: A response containing the daemon's configured paths.
    /// - Throws: `StoreError` if the read fails.
    func pathsGet() throws -> PathsGetResponse {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).pathsGet() }
    }

    /// Sets a daemon configuration key-value pair.
    /// - Parameter req: The configuration set request with key and value.
    /// - Returns: A response confirming the configuration was set.
    /// - Throws: `StoreError.badRequest` if the value is empty; other store errors otherwise.
    func configSet(_ req: ConfigSetRequest) throws -> ConfigSetResponse {
        let value = req.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw StoreError.badRequest(detail: "config value is empty")
        }
        return try boundary { db in
            try ConfigRepository(db: db, core: core).configSet(req, value: value)
        }
    }

    /// Reads a daemon configuration value by key.
    ///
    /// Returns nil until config exists. A daemon booted before m0002 seeded
    /// the table simply has no watcher and no configuration.
    /// - Parameter key: The configuration key to read.
    /// - Returns: The configuration value, or nil if not set.
    /// - Throws: `StoreError` if the read fails.
    func configValue(_ key: ConfigKey) throws -> String? {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).configValue(key) }
    }

    /// Looks up a prompt UUID by its gmfs folder path.
    /// - Parameter path: The gmfs folder path to look up.
    /// - Returns: The prompt UUID, or nil if not found.
    /// - Throws: `StoreError` if the read fails.
    func promptUuid(byStoragePath path: String) throws -> String? {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).promptUuid(byStoragePath: path) }
    }
}
