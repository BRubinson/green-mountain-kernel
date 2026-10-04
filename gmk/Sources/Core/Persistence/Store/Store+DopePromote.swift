import Foundation
import GRDB

// BASE_PROJECT promotion — the third sync direction. Full design rationale
// (high-water mark predicate, ping-pong and event-storm failure modes) lives
// atop DopePromoteRepository; this wrapper owns the transaction.

extension Store {
    /// Promote a dope scope from SESSION_INSTANCE to BASE_PROJECT tier.
    ///
    /// - Parameter req: The promotion request.
    /// - Returns: The promotion response.
    /// - Throws: Any database or validation error.
    func dopePromote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        try boundary { db in try DopePromoteRepository(db: db, core: core).promote(req) }
    }
}
