import Foundation
import GRDB

/// THE transaction boundary, and the whole of the shared-service-layer
/// deliverable.
///
/// ## Why this file exists
///
/// The kernel collapse put the UI, the relayed MCP surface and the daemon's own
/// background services in one process sharing one `DatabaseQueue`. The ask was
/// not merely "one connection pool" — it was **shared transaction boundaries**:
/// two verbs that must land together, or not at all.
///
/// The verb layer was already ready for that and nobody had noticed.
/// `RepositoryContext` is `{ db, core }` plus its named accessors, `StoreCore`
/// deliberately holds no queue and exposes no verb, and every verb body in this
/// module is already written against an **injected** `Database`. The only thing
/// hard-wired was the boundary itself, in 133 sites in this one directory. So
/// composition did not need a new vocabulary — it needed those 133 sites to
/// route through one function that knows whether a transaction is already open.
///
/// That is why there is no `uow:` parameter here and no per-verb wrapper. An
/// explicit unit-of-work parameter is the 96-verb retype wearing a different
/// hat: it has to appear in every signature the composition can reach, which is
/// exactly the second hand-maintained surface this design exists to avoid. The
/// ~120 already-`public` verbs on the `Store+*` extensions compose as they are.
///
/// ## The correctness condition, and why it is checked rather than assumed
///
/// The ambient handle is **thread-local**, not global. GRDB runs a `write` body
/// synchronously on one dedicated thread, and every nested verb call runs on
/// that same thread, so a thread-local is exactly scoped to one transaction. A
/// global would leak one transaction's handle into a concurrent caller and
/// corrupt both.
///
/// This is only correct while the verb layer performs **no thread hops inside a
/// boundary**. That holds today at zero occurrences — there is no
/// `DispatchQueue`, no `Task {`, no `async` and no `await` anywhere under
/// `Sources/GmDaemon/` or the handlers — and `TransactionBoundaryTests` pins it
/// so a future hop fails the build instead of silently splitting a transaction
/// across threads. If that test ever goes red the answer is to remove the hop,
/// not to relax the boundary.
extension Store {

    // MARK: - The ambient handle

    /// Thread-local key for the in-flight write transaction's `Database`.
    ///
    /// One key per process, created once. `pthread_key_create` is used directly
    /// rather than a `@TaskLocal` because the verb layer is synchronous and
    /// non-`async`: there is no task to attach to, and the value must follow the
    /// GRDB writer thread rather than a Swift concurrency context.
    private static let ambientKey: pthread_key_t = {
        var key = pthread_key_t()
        // No destructor: the value is an unretained pointer to a Database owned
        // by GRDB for the duration of the write block, and `boundary` always
        // clears it in a `defer`. A destructor could only ever double-free.
        pthread_key_create(&key, nil)
        return key
    }()

    /// The write transaction open on THIS thread, or nil.
    fileprivate static var ambient: Database? {
        get {
            guard let raw = pthread_getspecific(ambientKey) else { return nil }
            return Unmanaged<DatabaseReference>.fromOpaque(raw).takeUnretainedValue().db
        }
        set {
            // Release any previous box before replacing it, so a nested
            // set/clear pair cannot leak.
            if let raw = pthread_getspecific(ambientKey) {
                Unmanaged<DatabaseReference>.fromOpaque(raw).release()
                pthread_setspecific(ambientKey, nil)
            }
            guard let db = newValue else { return }
            let box = DatabaseReference(db: db)
            pthread_setspecific(ambientKey, Unmanaged.passRetained(box).toOpaque())
        }
    }

    /// Box so a non-object `Database` can round-trip through `pthread_specific`.
    fileprivate final class DatabaseReference {
        let db: Database
        init(db: Database) { self.db = db }
    }

    /// True when a write transaction is already open on this thread. Read by the
    /// four-phase repo verbs, which must refuse to run inside one.
    var isInTransaction: Bool { Store.ambient != nil }

    // MARK: - The boundary

    /// Replaces every `dbQueue.write` in this module.
    ///
    /// Enlists in the ambient transaction when one is open, so a verb called
    /// from inside `inTransaction` contributes to that transaction instead of
    /// opening its own — which is the entire mechanism. Without the enlist,
    /// calling a public verb inside a transaction would re-enter
    /// `DatabaseQueue.write`, and GRDB's re-entrancy check does not throw: it
    /// **traps**, killing the process.
    func boundary<T>(_ body: (Database) throws -> T) throws -> T {
        if let db = Store.ambient {
            return try body(db)
        }
        return try dbQueue.write { db in
            Store.ambient = db
            defer { Store.ambient = nil }
            return try body(db)
        }
    }

    /// Read twin of `boundary`.
    ///
    /// It MUST enlist under an ambient write, for two independent reasons.
    /// `DatabaseQueue` holds exactly ONE connection, so a `dbQueue.read` issued
    /// inside a `write` re-enters and traps; and even if it did not, it would be
    /// reading a different snapshot than the transaction it was called from —
    /// so a verb would silently fail to see writes its own caller had just
    /// made. Enlisting fixes both at once.
    func boundaryRead<T>(_ body: (Database) throws -> T) throws -> T {
        if let db = Store.ambient {
            return try body(db)
        }
        return try dbQueue.read(body)
    }

    // MARK: - The one new public API

    /// Runs `body` inside ONE transaction. Every existing public `Store` verb
    /// called within it enlists, and the whole composite commits or rolls back
    /// together:
    ///
    /// ```swift
    /// try store.inTransaction {
    ///     try store.promptSetStatus(...)
    ///     try store.archDecide(...)
    /// }
    /// ```
    ///
    /// Nesting is safe and idempotent — an inner `inTransaction` enlists in the
    /// outer one rather than opening a second — because it routes through
    /// `boundary` like everything else.
    ///
    /// Two things deliberately cannot be composed, and both fail loudly rather
    /// than misbehaving: `checkpointTruncate`, because a WAL checkpoint inside a
    /// transaction is illegal in SQLite, and the four-phase repo verbs, because
    /// they perform filesystem work between their read and their write and would
    /// hold the single writer lock across it. See `StoreError.notComposable`.
    public func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try boundary { _ in try body() }
    }
}
