import Foundation

/// PATHS_GET — typed runtime/gmfs/kbite roots from Paths + daemon_config.
enum PathsGetHandler {
    /// Handles a paths get request.
    ///
    /// - Parameters:
    ///   - line: The request payload data.
    ///   - head: The request envelope header.
    ///   - store: The store for path operations.
    /// - Returns: The handler result with paths data.
    /// - Throws: Any error from decoding or path operations.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        _ = try decodePayload(PathsGetRequest.self, from: line)
        return try okResult(.pathsGet, head, try store.pathsGet())
    }
}
