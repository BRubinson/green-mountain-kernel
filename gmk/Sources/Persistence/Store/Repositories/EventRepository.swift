import Foundation
import GRDB

/// Data access for daemon_event reads.
///
/// Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts.
struct EventRepository {
    let db: Database

    /// Lists daemon events matching the given filters.
    /// - Parameter req: The list request with optional filters.
    /// - Returns: A response containing the filtered events.
    /// - Throws: Any database error.
    func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        var request = DaemonEventRecord.all()
        if let kind = req.kind {
            request = request.filter(DaemonEventRecord.Columns.kind == kind)
        }
        if let subjectUuid = req.subjectUuid {
            request = request.filter(DaemonEventRecord.Columns.subjectUuid == subjectUuid)
        }
        if let sinceId = req.sinceId {
            request = request.filter(DaemonEventRecord.Columns.id > sinceId)
        }
        if let sinceTime = req.sinceTime {
            request = request.filter(DaemonEventRecord.Columns.createdAt >= sinceTime)
        }
        if let untilTime = req.untilTime {
            request = request.filter(DaemonEventRecord.Columns.createdAt <= untilTime)
        }
        let limit = min(max(req.limit ?? 200, 1), 10_000)
        let events =
            try request
            .order(DaemonEventRecord.Columns.id)
            .limit(limit)
            .fetchAll(db)
            .map { $0.dto() }
        return EventListResponse(events: events)
    }

    /// Returns the highest daemon_event.id, the SUBSCRIBE replay horizon.
    /// - Returns: The highest event id, or 0 if no events exist.
    /// - Throws: Any database error.
    func lastEventId() throws -> Int64 {
        try DaemonEventRecord
            .select(max(DaemonEventRecord.Columns.id) ?? 0, as: Int64.self)
            .fetchOne(db) ?? 0
    }
}
