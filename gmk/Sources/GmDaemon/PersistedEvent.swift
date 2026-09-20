import Foundation

/// A committed daemon_event row, as delivered to the event sink. `id` is the
/// durable cursor shared by live broadcast and since_id replay.
public struct PersistedEvent: Sendable {
    public let id: Int64
    public let kind: String
    public let subjectUuid: String?
    public let payload: String?
    public let createdAt: String

    public var notification: EventNotification {
        EventNotification(id: id, kind: kind, subjectUuid: subjectUuid, payload: payload, createdAt: createdAt)
    }
}
