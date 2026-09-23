import Foundation

/// DOPE_NODE_ADD — level-parameterized child insert (the DopeLevelSpec
/// registry maps level → table/parent/legal fields).
enum DopeNodeAddHandler {
    /// Handle a DOPE_NODE_ADD request.
    ///
    /// - Parameters:
    ///   - line: The payload data.
    ///   - head: The envelope head.
    ///   - store: The kernel store.
    /// - Returns: The handler result.
    /// - Throws: Any request or database error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeNodeAddRequest.self, from: line)
        return try okResult(.dopeNodeAdd, head, try store.dopeNodeAdd(request))
    }
}
