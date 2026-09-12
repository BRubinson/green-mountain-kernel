import Foundation
import GRDB

// BASE_PROJECT promotion — the third sync direction. Full design rationale
// (high-water mark predicate, ping-pong and event-storm failure modes) lives
// atop DopePromoteRepository; this wrapper owns the transaction.

extension Store {
    public func dopePromote(_ req: DopePromoteRequest) throws -> DopePromoteResponse {
        try dbQueue.write { db in try DopePromoteRepository(db: db, core: core).promote(req) }
    }
}
