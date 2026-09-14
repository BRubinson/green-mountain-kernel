import Foundation
import GmDaemon
import GmDaemonSdk

/// The headless kernel host — what `gm_kernel daemon` (and the `gm_daemon`
/// symlink) runs.
///
/// ## Why a headless personality still exists
///
/// The kernel is meant to be the app: a menu-bar-resident process that owns the
/// database and opens vibe windows. It would have been tidier to make the app
/// bundle the ONLY shape that can open the db, and that shape was seriously
/// considered — it reduces "two writers" from two possible causes to one.
///
/// It does not survive contact with how clients actually start the writer.
/// `DaemonClient.autostart()` `posix_spawn`s a binary when no socket answers, and
/// that call happens inside Claude Code hooks, over SSH, and in CI. None of those
/// contexts can launch an application: LaunchServices is unavailable, and
/// spawning a GUI binary directly produces an AppKit process that LaunchServices
/// does not know about — which is to say a SECOND WRITER, created on every hook
/// call, by the very mechanism meant to make the writer available.
///
/// So this host stays, AppKit-free, and the app takes over from it when a person
/// launches the app. See `KernelOwnership` for the handover.
///
/// ## Boot order, and which parts are load-bearing
///
///   1. take the ownership lock — BEFORE anything can open the database
///   2. redirect stdout/stderr into `~/gmfs/daemon.log`
///   3. open + (back up, if pending) + migrate + record DAEMON_START
///   4. bind the socket, serve, `dispatchMain()`
///
/// Step 1 first is the invariant. Steps 2 and 3 are in that order so a db failure
/// is written to the log rather than to a stderr nobody is reading.
public enum KernelHost {

    /// Run as the headless writer. Never returns.
    public static func bootHeadlessAndRun() -> Never {
        let outcome: KernelOwnership.Outcome
        do {
            outcome = try KernelOwnership.acquire()
        } catch {
            FileHandle.standardError.write(Data("[gm_kernel] \(error)\n".utf8))
            exit(1)
        }

        let token: KernelOwnership.Token
        switch consume outcome {
        case .heldBy:
            // A redundant autostart, and NOT an error — deliberately exit 0.
            //
            // Client autostart races are normal: two hooks firing at once both
            // see no socket and both spawn. The loser exiting 0 silently is what
            // makes that harmless, and `DaemonClient.autostart()` depends on this
            // exit code to distinguish "someone else got there first" from "the
            // binary is broken". An app host behaves differently on this branch —
            // it degrades to client mode rather than exiting — because quitting a
            // window the user just opened is not a silent no-op.
            exit(0)
        case .acquired(let acquired):
            token = acquired
        }

        // --- log redirection ----------------------------------------------
        let logFd = open(Paths.log.path, O_CREAT | O_WRONLY | O_APPEND, 0o644)
        if logFd >= 0 {
            dup2(logFd, STDOUT_FILENO)
            dup2(logFd, STDERR_FILENO)
        }

        func log(_ message: String) {
            print("[\(Store.isoNow())] \(message)")
            fflush(stdout)
        }

        // --- the writer + the server --------------------------------------
        // ONE sequence, shared with the app host. `KernelServices.bootWriter`
        // opens the database, refuses one written by newer bits, takes the
        // pre-migration backup when the ledger is behind, migrates, records the
        // start and binds the socket. It THROWS rather than exiting, because an
        // app has to be able to show the refusal; here, exiting is right.
        //
        // Watchers (memory + checkout) are owned by the Server's
        // WatcherSupervisor, built inside server.start() and rebuilt on
        // CONFIG_SET / CREATE_INSTANCE through the post-commit fan-out. The
        // supervisor's first rebuild logs the watched state.
        let services: KernelServices
        do {
            services = try KernelServices.bootWriter(
                consume token, personality: "headless", log: log)
        } catch {
            log("db bootstrap failed: \(error)")
            exit(1)
        }

        // --- signals ------------------------------------------------------
        // THE HEADLESS SHUTDOWN STILL EXITS. `Server.shutdown()` ends in
        // exit(0) after the goodbye lands, which is what a signalled daemon
        // should do and what `KernelHostRole.takeOver` relies on: an app taking
        // over sends SIGTERM and then polls for the lock, so this process must
        // actually go away rather than merely stop serving.
        //
        // The app host takes the OTHER door — `KernelServices.shutdown` — which
        // performs the same ordered teardown and does not exit.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            log("SIGTERM — shutting down")
            services.serverShutdownAndExit()
        }
        sigtermSource.resume()
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            log("SIGINT — shutting down")
            services.serverShutdownAndExit()
        }
        sigintSource.resume()

        dispatchMain()
    }
}
