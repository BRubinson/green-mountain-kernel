import Foundation
import GRDB

/// THE transaction boundary: one process shares one `DatabaseQueue`, and what
/// it needs is shared transaction boundaries — two verbs that land together or
/// not at all. Every verb body is written against an INJECTED `Database`, so
/// the 133 boundary sites route through one function that knows whether a
/// transaction is already open. There is deliberately no `uow:` parameter.
/// The ambient handle is THREAD-LOCAL, not global, and is correct only while
/// the verb layer performs NO THREAD HOPS inside a boundary. Remove a hop;
/// never relax the boundary.
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
        /// Creates a reference to a database.
        /// - Parameter db: The database to reference.
        init(db: Database) { self.db = db }
    }

    /// True when a write transaction is already open on this thread.
    ///
    /// Read by the four-phase repo verbs, which must refuse to run inside one.
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
    /// - Parameter body: A closure that performs database operations.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error from `body` or the database operation.
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
    /// - Parameter body: A closure that performs database read operations.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error from `body` or the database operation.
    func boundaryRead<T>(_ body: (Database) throws -> T) throws -> T {
        if let db = Store.ambient {
            return try body(db)
        }
        return try dbQueue.read(body)
    }

    // MARK: - The one new public API

    /// Runs `body` inside ONE transaction.
    ///
    /// Every existing public `Store` verb called within it enlists, and the whole composite commits or rolls back
    /// together. Nesting is safe and idempotent: an inner `inTransaction` enlists in the outer one rather than opening
    /// a second. Two things deliberately cannot compose and fail loudly instead — `checkpointTruncate`, since a WAL
    /// checkpoint inside a transaction is illegal in SQLite, and the four-phase repo verbs, which would hold the single
    /// writer across filesystem work.
    /// - Parameter body: A closure containing the operations to run in the transaction.
    /// - Returns: The value returned by `body`.
    /// - Throws: Any error from `body` or the transaction itself.
    func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try boundary { _ in try body() }
    }
}
