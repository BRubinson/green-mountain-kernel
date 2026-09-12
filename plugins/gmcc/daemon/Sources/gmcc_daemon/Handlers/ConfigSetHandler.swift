import Foundation
import GMCCDaemonKit

/// CONFIG_SET — write one enum-bound daemon_config key.
enum ConfigSetHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ConfigSetRequest.self, from: line)
        return try okResult(.configSet, head, try store.configSet(request))
    }
}
