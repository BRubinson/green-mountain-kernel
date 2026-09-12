import Foundation
import GRDB

/// Data access for daemon_event reads. Runs INSIDE a Store-owned transaction;
/// holds no dbQueue and never self-transacts.
struct EventRepository {
    let db: Database

    func listEvents(_ req: EventListRequest) throws -> EventListResponse {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let kind = req.kind {
            conditions.append("kind = ?")
            arguments.append(kind)
        }
        if let subjectUuid = req.subjectUuid {
            conditions.append("subject_uuid = ?")
            arguments.append(subjectUuid)
        }
        if let sinceId = req.sinceId {
            conditions.append("id > ?")
            arguments.append(sinceId)
        }
        if let sinceTime = req.sinceTime {
            conditions.append("created_at >= ?")
            arguments.append(sinceTime)
        }
        if let untilTime = req.untilTime {
            conditions.append("created_at <= ?")
            arguments.append(untilTime)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let limit = min(max(req.limit ?? 200, 1), 10_000)
        let events = try DaemonEventRecord.fetchAll(
            db,
            sql: """
                SELECT * FROM daemon_event
                \(whereClause)
                ORDER BY id
                LIMIT \(limit)
                """,
            arguments: StatementArguments(arguments)
        ).map { $0.wireNotification() }
        return EventListResponse(events: events)
    }

    /// Highest daemon_event.id — the replay horizon SUBSCRIBE acks with.
    func lastEventId() throws -> Int64 {
        try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(id), 0) FROM daemon_event") ?? 0
    }
}
