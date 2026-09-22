import Foundation
import GRDB

/// Data access for daemon_event reads. Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts.
struct EventRepository {
    let db: Database

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

    /// Highest daemon_event.id — the replay horizon SUBSCRIBE acks with.
    func lastEventId() throws -> Int64 {
        try DaemonEventRecord
            .select(max(DaemonEventRecord.Columns.id) ?? 0, as: Int64.self)
            .fetchOne(db) ?? 0
    }
}
