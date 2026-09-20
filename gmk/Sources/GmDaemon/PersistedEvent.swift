import Foundation

/// A committed daemon_event row, as delivered to the event sink. `id` is the
/// durable cursor shared by live broadcast and since_id replay.
struct PersistedEvent: Sendable {
    let id: Int64
    let kind: String
    let subjectUuid: String?
    let payload: String?
    let createdAt: String

    var notification: EventNotification {
        EventNotification(id: id, kind: kind, subjectUuid: subjectUuid, payload: payload, createdAt: createdAt)
    }
}
