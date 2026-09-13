import Foundation
import GmDaemon
import GmDaemonSdk

/// The ONLY thing in the tree that opens the database for writing.
///
/// `start` consumes a `KernelOwnership.Token`, which only a won `flock` can
/// produce. That is the whole design: "did we take the lock first?" stops being a
/// question about control flow and becomes a question the compiler answers. A
/// source-scan contract test (`KernelHostContractTests`) asserts that no other
/// file outside `Store.swift` and the test suites names `Store(path:`, so the
/// next person who reaches for a convenient `Store(path: …)` gets a failing build
/// instead of a second writer.
public final class KernelWriter {

    public let store: Store
    /// Held for the process's lifetime. Never closed deliberately: the kernel
    /// releasing it at exit is what makes a crash leave no stale lock.
    private let token: KernelOwnership.Token

    /// Open, back up if a migration is pending, migrate, record the start.
    ///
    /// - Parameters:
    ///   - token: consumed proof of exclusive ownership.
    ///   - log: where progress goes. Injected because the headless host writes to
    ///     `~/gmfs/daemon.log` while an app host wants it in the unified log.
    public static func start(
        _ token: consuming KernelOwnership.Token,
        log: (String) -> Void = { _ in }
    ) throws -> KernelWriter {
        let store = try Store(path: Paths.db.path)

        // THE PRE-MIGRATION BACKUP, and why it is automatic rather than advised.
        //
        // The snapshot dev loop used to be the rehearsal surface for schema
        // change: you ran the migration against a copy first. Deleting it (which
        // is what removed the wrong-root hazard) also removed that rehearsal, and
        // the honest replacement is not a louder instruction in a skill file —
        // it is the machine taking the snapshot. A migration is the one operation
        // here that rewrites history rather than appending to it, so it is the
        // one that must not run un-snapshotted.
        //
        // Only when the ledger is actually behind: an up-to-date kernel starting
        // for the thousandth time must not copy a ~800MB database every launch.
        // REFUSE A DATABASE FROM THE FUTURE, before touching it.
        //
        // The check below catches a db BEHIND this binary. This one catches a
        // db AHEAD of it, which is the direction nothing caught and which fails
        // SILENTLY: GRDB applies unapplied registered migrations and does not
        // object to applied ones it has never heard of, so an older kernel
        // opening a newer database sees no pending work and simply carries on —
        // writing rows through a model that disagrees with the schema.
        //
        // With more than one environment on a machine this stops being
        // theoretical. A root seeded from a newer source, or a stale
        // `releases/active` in one root while another was rebuilt, reaches it
        // on an ordinary day.
        //
        // Refusing loudly here costs a confusing startup failure. Not refusing
        // costs quiet corruption of an append-only database, which is not
        // recoverable by any amount of care afterwards.
        if try store.hasBeenSuperseded() {
            throw StoreError.corruptState(
                entity: "schema",
                detail: "\(Paths.db.path) carries migrations this binary does not know — "
                    + "it was written by NEWER bits (this kernel is at schema "
                    + "\(Migrations.currentSchemaVersion)). Refusing to open it rather than "
                    + "writing through a schema we cannot model. Update the binaries in this "
                    + "root, or point GM_FS_ROOT at the environment these bits belong to.")
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
