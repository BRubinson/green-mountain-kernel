import Foundation

/// EVENT_LIST — query the daemon_event log by kind/subject/id/time range.
///
/// The queryable audit trail; kind travels as a raw string.
enum EventListHandler {
    /// Handles an EVENT_LIST request.
    ///
    /// - Parameters:
    ///   - line: The NDJSON line containing the request.
    ///   - head: The envelope head with protocol version and request id.
    ///   - store: The store to query events from.
    /// - Returns: The handler result with the event list response.
    /// - Throws: Decoding errors or store errors.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(EventListRequest.self, from: line)
        return try okResult(.eventList, head, try store.listEvents(request))
    }
}
