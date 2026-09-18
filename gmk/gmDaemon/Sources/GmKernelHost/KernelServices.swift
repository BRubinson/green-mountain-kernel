import Foundation
import GmDaemon
import GmDaemonSdk

/// The kernel, as something an application can HOLD.
///
/// ## Why this type exists
///
/// `KernelHost.bootHeadlessAndRun()` was the only door into the writer, and
/// every one of its properties is wrong for an app: it returns `Never`, it
/// `exit`s when it loses the lock, it `dup2`s stdout and stderr into
/// `~/gmfs/daemon.log`, and it ends in `dispatchMain()`. Those are all correct
/// for a headless process and none of them can appear inside `App.init()`.
///
/// So the ORDER — take the lock, open, back up if pending, migrate, bind, serve
/// — moved here, and `bootHeadlessAndRun` now composes this type rather than
/// spelling the sequence a second time. Two copies of that sequence is the kind
/// of duplication that stays correct for a year and then silently does not.
///
/// ## What it deliberately does NOT do
///
/// No `exit()`, anywhere. No signal handling. No `dispatchMain()`. No log
/// redirection. Each of those belongs to a PERSONALITY, and both personalities
/// keep their own — see `Boot.swift` for the headless one and `GMVibesServices`
/// for the app.
///
/// ## Ownership is still the type's job
///
/// `bootWriter` consumes a `KernelOwnership.Token`, which only a won `flock` can
/// produce. Adding this second host did not weaken that: there is still exactly
/// one `Store(path:)` site in the tree, still reachable only by consuming a
/// token, and a losing process still cannot open the database because no
/// expression exists that opens it.
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

    /// Open the database, migrate it, and start serving.
    ///
    /// - Parameters:
    ///   - token: consumed proof of exclusive ownership. Only `acquire()` mints
    ///     one, so "did we take the lock first?" is answered by the compiler.
    ///   - log: where progress goes. Injected because the headless host writes
    ///     to `~/gmfs/daemon.log` and an app host wants the unified log.
    ///
    /// THROWS RATHER THAN EXITS. A schema written by newer bits makes
    /// `KernelWriter.start` refuse (see its `hasBeenSuperseded` check), and a
    /// refusal an app can catch and SHOW beats a process that vanished.
    ///   - personality: named in the ready line only, so a log reader can tell
    ///     a headless kernel from an app-hosted one at a glance. The two are
    ///     otherwise indistinguishable on the wire and in the pidfile's first
    ///     two lines — it is the THIRD line, the bundle path, that actually
    ///     distinguishes them, and nobody reads a log for that.
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
                + "listening at \(Paths.socket.path) [\(personality)]")
        return KernelServices(writer: writer, server: server)
    }

    /// The in-process verb caller — a `GmVerbCaller` that re-enters the
    /// dispatcher instead of dialling the socket.
    ///
    /// This is what makes the collapse worth anything. Every one of the ~110
    /// verb methods is declared in `extension GmVerbCaller`, and
    /// `DaemonClient: GmVerbCaller {}` is an EMPTY conformance — so a consumer
    /// written against the socket client runs unchanged against this, reaching
    /// all 96 handlers with the same decode, the same guards and the same error
    /// envelopes, minus one hop.
    ///
    /// `from: nil` marks the call as in-process. The only verb that needs a
    /// connection is SUBSCRIBE, which is refused here on purpose: an in-process
    /// consumer subscribes through `store.subscribeToEvents` instead.
    public var verbCaller: any GmVerbCaller {
        KernelVerbCaller(dispatch: { [server] line in
            server.dispatch(line: line, from: nil)
        })
    }

    /// Stop serving and close the database, in the one order that is correct.
    ///
    ///   1. cancel the listener, so nothing new arrives
    ///   2. unsubscribe from post-commit events
    ///   3. record DAEMON_STOP and send the goodbye
    ///   4. `beforeClose()` — the caller's last in-process write
    ///   5. checkpoint the WAL, close the database, unlink socket and pidfile
    ///
    /// Step 4's position is the whole point. The app's dirty prompt-edit flush
    /// used to travel through the SOCKET, which is an ordering inversion the
    /// moment both ends are one process — and it has to run before the store
    /// closes but after the listener stops, or a write can arrive after the
    /// flush has already decided what was dirty.
    ///
    /// The lock is NOT released here. It lives for the process, and letting the
    /// kernel drop it at exit is what makes a CRASHED kernel leave no stale
    /// lock behind.
    public func shutdown(beforeClose: () -> Void = {}) {
        server.shutdownForHost(beforeClose: beforeClose)
    }

    /// The HEADLESS shutdown: the same teardown, ending in `exit(0)`.
    ///
    /// Kept distinct from `shutdown(beforeClose:)` rather than given a flag,
    /// because the difference is not a preference. A signalled headless kernel
    /// MUST actually terminate: `KernelHostRole.takeOver` sends it SIGTERM and
    /// then polls for the lock, and a process that stopped serving but stayed
    /// alive still holds the `flock` — so the app would wait out its timeout
    /// and settle for client mode against a kernel that is no longer listening.
    func serverShutdownAndExit() {
        server.shutdown()
    }
}
