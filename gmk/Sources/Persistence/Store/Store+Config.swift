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
    func pathsGet() throws -> PathsGetResponse {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).pathsGet() }
    }

    func configSet(_ req: ConfigSetRequest) throws -> ConfigSetResponse {
        let value = req.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw StoreError.badRequest(detail: "config value is empty")
        }
        return try boundary { db in
            try ConfigRepository(db: db, core: core).configSet(req, value: value)
        }
    }

    /// The watcher's root, read outside a request cycle. nil until config
    /// exists (a daemon booted before m0002 seeded it simply has no watcher).
    func configValue(_ key: ConfigKey) throws -> String? {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).configValue(key) }
    }

    /// MemoryWatcher's reverse lookup: prompt by its gmfs folder path.
    func promptUuid(byStoragePath path: String) throws -> String? {
        try boundaryRead { db in try ConfigRepository(db: db, core: core).promptUuid(byStoragePath: path) }
    }
}
