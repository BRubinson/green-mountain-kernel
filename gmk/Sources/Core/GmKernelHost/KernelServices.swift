import Foundation

/// The kernel, as something a process can HOLD: the ONE boot sequence —
/// take the lock, open, back up if pending, migrate, bind, serve — used by the
/// app and by the test harness.
///
/// It does no `exit()`, no signal handling and no log redirection; how the
/// process ends belongs to the host. `bootWriter` consumes a
/// `KernelOwnership.Token`, so a losing process has no expression that opens
/// the database.
final class KernelServices {

    /// The open database.
    ///
    /// Public because the app host needs it for in-process event subscription; it is NOT
    /// re-exported past `GMVibesServices`, which keeps a deliberately narrow facade.
    let store: Store

    private let writer: KernelWriter
    private let server: Server

    /// Creates kernel services with a writer and server.
    ///
    /// - Parameters:
    ///   - writer: The kernel writer managing the database.
    ///   - server: The message server.
    private init(writer: KernelWriter, server: Server) {
        self.writer = writer
        self.server = server
        self.store = writer.store
    }

    /// Opens the database, migrates it, and starts the server.
    ///
    /// Throws rather than exits: a schema written by newer bits makes `KernelWriter.start`
    /// refuse, and a refusal an app can catch and show beats a process that vanished.
    ///
    /// - Parameters:
    ///   - token: The kernel ownership token from the host.
    ///   - log: A callback for log messages; defaults to ignoring them.
    /// - Returns: The kernel services instance.
    /// - Throws: `KernelError` on database or server startup failures.
    static func bootWriter(
        _ token: consuming KernelOwnership.Token,
        log: @escaping (String) -> Void = { _ in }
    ) throws -> KernelServices {
        let writer = try KernelWriter.start(consume token, log: log)
        let server = try Server(store: writer.store)
        server.start()
        // Only a process that actually took the lock says "writer". A client
        // never reaches this function, so this assignment cannot lie.
        KernelVitalsSource.writerRole = "writer"
        log(
            "kernel pid \(getpid()) protocol v\(GmWireProtocol.version) "
                + "listening at \(Paths.socket.path) [hosted]"
        )
        return KernelServices(writer: writer, server: server)
    }

    /// The in-process verb caller — a `GmVerbCaller` that re-enters the dispatcher instead of dialling the socket.
    ///
    /// Every verb method is declared in `extension GmVerbCaller` and `DaemonClient: GmVerbCaller {}`
    /// is an EMPTY conformance, so a consumer written against the socket client runs unchanged here.
    /// `from: nil` marks the call in-process, which refuses SUBSCRIBE: an in-process consumer uses
    /// `store.subscribeToEvents`.
    var verbCaller: any GmVerbCaller {
        KernelVerbCaller(dispatch: { [server] line in
            server.dispatch(line: line, from: nil)
        })
    }

    /// The STATUS answer read in-process, built by the same code the STATUS verb uses.
    ///
    /// - Returns: The daemon status response.
    /// - Throws: Persistence errors from the schema, count or event-id reads.
    func status() throws -> StatusResponse {
        try server.statusResponse()
    }

    /// The STATUS read as a closure the app's service actor can hold across its queue hop.
    ///
    /// Captures only the server, which is Sendable; this type is not, so it never crosses the
    /// actor boundary itself.
    var statusBuilder: @Sendable () throws -> StatusResponse {
        let server = self.server
        return { try server.statusResponse() }
    }

    /// Stops serving and closes the database in the correct order.
    ///
    /// Cancels the listener, unsubscribes from post-commit events, records DAEMON_STOP
    /// and sends the goodbye, runs `beforeClose()`, then checkpoints, closes and unlinks.
    /// `beforeClose` must run after the listener stops and before the store closes, or a
    /// write can arrive after the caller has decided what was dirty. The lock is not
    /// released here: it lives for the process, so a crashed kernel leaves no stale lock.
    ///
    /// - Parameter beforeClose: A callback to run before closing the store.
    func shutdown(beforeClose: () -> Void = {}) {
        server.shutdownForHost(beforeClose: beforeClose)
    }

    /// Installs what the host does when SHUTDOWN or a newer-protocol client asks the kernel to stop.
    ///
    /// The kernel never ends its process. A host that installs nothing ignores the request.
    ///
    /// - Parameter handler: The host's stop routine, called on the server queue.
    func onShutdownRequest(_ handler: @escaping @Sendable () -> Void) {
        server.setShutdownRequestHandler(handler)
    }
}
