import Foundation
import GMCCDaemonKit

/// PATHS_GET — typed runtime/ckfs/kbite roots from Paths + daemon_config.
enum PathsGetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(PathsGetRequest.self, from: line)
        return try okResult(.pathsGet, head, try store.pathsGet())
    }
}
