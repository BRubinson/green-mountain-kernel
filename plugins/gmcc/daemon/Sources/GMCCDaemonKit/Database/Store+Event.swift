import Foundation
import GRDB

// EVENT_LIST — the queryable audit trail, plus the replay read SUBSCRIBE uses.
// Bodies live in EventRepository; these wrappers own the transaction.

extension Store {
    public func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        try dbQueue.read { db in try EventRepository(db: db).listEvents(req) }
    }

    /// Highest daemon_event.id — the replay horizon SUBSCRIBE acks with.
    public func lastEventId() throws -> Int64 {
        try dbQueue.read { db in try EventRepository(db: db).lastEventId() }
    }
}
