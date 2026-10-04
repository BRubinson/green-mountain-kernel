import Foundation

/// PROMPT_SET_STATUS — validated lifecycle transition over the three-state
/// prompt lifecycle (draft → initiated → done, and done → draft to re-open);
/// emits PROMPT_STATUS_CHANGE.
enum PromptSetStatusHandler {
    /// Handles a prompt status change request and validates the transition.
    /// - Parameters:
    ///   - line: The request data containing the status change details.
    ///   - head: The envelope header for the request.
    ///   - store: The data store for persisting the status change.
    /// - Returns: A handler result with the set status response.
    /// - Throws: `StoreError` if the transition is invalid or the store operation fails.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(PromptSetStatusRequest.self, from: line)
        return try okResult(.promptSetStatus, head, try store.setPromptStatus(request))
    }
}
