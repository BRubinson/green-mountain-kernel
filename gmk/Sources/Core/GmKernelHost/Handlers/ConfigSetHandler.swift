import Foundation

/// CONFIG_SET — write one enum-bound daemon_config key.
enum ConfigSetHandler {
    /// Handles a CONFIG_SET request to write a daemon configuration key.
    ///
    /// - Parameters:
    ///   - line: The encoded request data.
    ///   - head: The message envelope header.
    ///   - store: The persistence store.
    /// - Returns: The handler result with the response.
    /// - Throws: Any error from decoding or the store.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ConfigSetRequest.self, from: line)
        return try okResult(.configSet, head, try store.configSet(request))
    }
}
