import Foundation

/// The ONLY thing in the tree that opens the database for writing. `start`
/// consumes a `KernelOwnership.Token`, which only a won `flock` can produce, so
/// "did we take the lock first?" is a question the compiler answers. A second
/// `Store(path:)` site anywhere is a second writer.
final class KernelWriter {

    let store: Store
    /// Held for the process's lifetime. Never closed deliberately: the kernel
    /// releasing it at exit is what makes a crash leave no stale lock.
    private let token: KernelOwnership.Token

    /// Open, back up if a migration is pending, migrate, record the start.
    /// `token` is consumed proof of exclusive ownership; `log` is injected
    /// because the headless host writes to the daemon log and an app host does
    /// not.
    static func start(
        _ token: consuming KernelOwnership.Token,
        log: (String) -> Void = { _ in }
    ) throws -> KernelWriter {
        let store = try Store(path: Paths.db.path)

        // REFUSE A DATABASE FROM THE FUTURE, before touching it. GRDB applies
        // unapplied registered migrations and raises nothing for applied ones it
        // has never heard of, so an older kernel opening a newer database sees no
        // pending work and writes rows through a schema it cannot model.
        //
        // The pre-migration backup below is automatic because a migration is the
        // one operation here that rewrites history rather than appending, and it
        // fires only when the ledger is behind, never on an ordinary launch.
        if try store.hasBeenSuperseded() {
            throw StoreError.corruptState(
                entity: "schema",
                detail: "\(Paths.db.path) carries migrations this binary does not know — "
                    + "it was written by NEWER bits (this kernel is at schema "
                    + "\(Migrations.currentSchemaVersion)). Refusing to open it rather than "
                    + "writing through a schema we cannot model. Update the binaries in this "
                    + "root, or point GM_FS_ROOT at the environment these bits belong to."
            )
        }

        if try store.hasPendingMigrations() {
            let destination = try store.backupBeforeMigration()
            log("pre-migration backup: \(destination)")
        }

        try store.migrate()
        try store.recordDaemonStart()
        return KernelWriter(store: store, token: consume token)
    }

    private init(store: Store, token: consuming KernelOwnership.Token) {
        self.store = store
        self.token = consume token
    }
}
