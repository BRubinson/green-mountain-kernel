import Foundation

/// SESSION_RESOLVE — session row + git-derived checked-out state (.git/HEAD read, no subprocess).
enum SessionResolveHandler {
    /// Handles SESSION_RESOLVE request to get session row and git state.
    ///
    /// Reads `.git/HEAD` directly without spawning a subprocess.
    ///
    /// - Parameters:
    ///   - line: The encoded request payload.
    ///   - head: The envelope header.
    ///   - store: The store instance.
    /// - Returns: A handler result with the session resolve response.
    /// - Throws: Any decoding or store error.
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(SessionResolveRequest.self, from: line)
        return try okResult(.sessionResolve, head, try store.sessionResolve(request))
    }
}
