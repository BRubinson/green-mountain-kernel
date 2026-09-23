import Foundation

/// The kernel, as something an application can HOLD: the ONE boot sequence —
/// take the lock, open, back up if pending, migrate, bind, serve — composed by
/// both personalities rather than spelled twice.
///
/// It does no `exit()`, no signal handling, no `dispatchMain()` and no log
/// redirection; each of those belongs to a PERSONALITY. `bootWriter` consumes a
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
    /// `personality` appears in the ready line only, so a log reader can tell a headless
    /// kernel from an app-hosted one.
    ///
    /// - Parameters:
    ///   - token: The kernel ownership token from the host.
    ///   - personality: A label for the kernel role; defaults to `"hosted"`.
    ///   - log: A callback for log messages; defaults to ignoring them.
    /// - Returns: The kernel services instance.
    /// - Throws: `KernelError` on database or server startup failures.
    static func bootWriter(
        _ token: consuming KernelOwnership.Token,
        personality: String = "hosted",
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
                + "listening at \(Paths.socket.path) [\(personality)]"
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

    /// The HEADLESS shutdown: the same teardown, ending in `exit(0)`.
    ///
    /// A signalled headless kernel MUST actually terminate — `KernelHostRole` polls for the
    /// lock after SIGTERM, and a process that stopped serving but stayed alive still holds
    /// the `flock`.
    func serverShutdownAndExit() {
        server.shutdown()
    }
}
