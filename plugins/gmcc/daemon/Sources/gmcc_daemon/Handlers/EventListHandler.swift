import Foundation
import GMCCDaemonKit

/// EVENT_LIST — query the daemon_event log by kind/subject/id/time range.
/// The queryable audit trail; kind travels as a raw string.
enum EventListHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(EventListRequest.self, from: line)
        return try okResult(.eventList, head, try store.listEvents(request))
    }
}
