import Foundation
import GmDaemon
import GmDaemonSdk

/// ARCH_GET — summary plus ordered change rows, decorated with derived
/// implementation state, unplanned changes, and the persistence-first audit.
enum ArchGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ArchGetRequest.self, from: line)
        return try okResult(.archGet, head, try store.archGet(request))
    }
}
