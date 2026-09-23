import Foundation
import GRDB

// EVENT_LIST — the queryable audit trail, plus the replay read SUBSCRIBE uses.
// Bodies live in EventRepository; these wrappers own the transaction.

extension Store {
    /// Lists events from the audit trail.
    ///
    /// - Parameter req: The list request with optional filtering.
    /// - Returns: The list of events.
    /// - Throws: Database errors.
    func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        try boundaryRead { db in try EventRepository(db: db).listEvents(req) }
    }

    /// Returns the highest event ID in the audit trail.
    ///
    /// The highest `daemon_event.id` — the replay horizon SUBSCRIBE acks with.
    ///
    /// - Returns: The highest event ID.
    /// - Throws: Database errors.
    func lastEventId() throws -> Int64 {
        try boundaryRead { db in try EventRepository(db: db).lastEventId() }
    }
}
