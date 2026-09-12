import Foundation
import GMCCDaemonKit

/// SEARCH — FTS5 ranked stubs with prompt lineage over
/// prompt/clarification/architecture text, optionally session-scoped.
enum SearchHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SearchRequest.self, from: line)
        return try okResult(.search, head, try store.search(request))
    }
}
