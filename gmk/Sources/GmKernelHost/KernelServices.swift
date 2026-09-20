import Foundation

/// The kernel, as something an application can HOLD: the ONE boot sequence —
/// take the lock, open, back up if pending, migrate, bind, serve — composed by
/// both personalities rather than spelled twice.
///
/// It does no `exit()`, no signal handling, no `dispatchMain()` and no log
/// redirection; each of those belongs to a PERSONALITY. `bootWriter` consumes a
/// `KernelOwnership.Token`, so a losing process has no expression that opens
/// the database.
public final class KernelServices {

    /// The open database. Public because the app host needs it for in-process
    /// event subscription; it is NOT re-exported past `GMVibesServices`, which
    /// keeps a deliberately narrow facade.
    public let store: Store

    private let writer: KernelWriter
    private let server: Server

    private init(writer: KernelWriter, server: Server) {
        self.writer = writer
        self.server = server
        self.store = writer.store
    }

    /// Open the database, migrate it, and start serving. THROWS RATHER THAN
    /// EXITS: a schema written by newer bits makes `KernelWriter.start` refuse,
    /// and a refusal an app can catch and SHOW beats a process that vanished.
    /// `personality` appears in the ready line only, so a log reader can tell a
    /// headless kernel from an app-hosted one.
    public static func bootWriter(
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

    /// The in-process verb caller — a `GmVerbCaller` that re-enters the
    /// dispatcher instead of dialling the socket. Every verb method is declared
    /// in `extension GmVerbCaller` and `DaemonClient: GmVerbCaller {}` is an
    /// EMPTY conformance, so a consumer written against the socket client runs
    /// unchanged here. `from: nil` marks the call in-process, which refuses
    /// SUBSCRIBE: an in-process consumer uses `store.subscribeToEvents`.
    public var verbCaller: any GmVerbCaller {
        KernelVerbCaller(dispatch: { [server] line in
            server.dispatch(line: line, from: nil)
        })
    }

    /// Stop serving and close the database, in the one correct order: cancel
    /// the listener, unsubscribe from post-commit events, record DAEMON_STOP and
    /// send the goodbye, run `beforeClose()`, then checkpoint, close and unlink.
    /// `beforeClose` must run after the listener stops and before the store
    /// closes, or a write can arrive after the caller has decided what was
    /// dirty. The lock is NOT released here: it lives for the process, so a
    /// CRASHED kernel leaves no stale lock behind.
    public func shutdown(beforeClose: () -> Void = {}) {
        server.shutdownForHost(beforeClose: beforeClose)
    }

    /// The HEADLESS shutdown: the same teardown, ending in `exit(0)`. A
    /// signalled headless kernel MUST actually terminate — `KernelHostRole`
    /// polls for the lock after SIGTERM, and a process that stopped serving but
    /// stayed alive still holds the `flock`.
    func serverShutdownAndExit() {
        server.shutdown()
    }
}
