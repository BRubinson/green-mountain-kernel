import Foundation

/// The headless, AppKit-free kernel host — what `gm_kernel daemon` (and the
/// `gm_daemon` symlink) runs. `DaemonClient.autostart()` `posix_spawn`s a binary
/// from hooks, SSH and CI, where LaunchServices cannot launch an app and
/// spawning a GUI binary directly mints an untracked second writer.
///
/// Boot order is load-bearing: the ownership lock comes first, so nothing can
/// open the database before it, and log redirection precedes the db work so a
/// failure lands in the log rather than an unread stderr.
enum KernelHost {

    /// Run as the headless writer.
    ///
    /// Never returns.
    static func bootHeadlessAndRun() -> Never {
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
            // A redundant autostart, not an error: two hooks racing both spawn,
            // and `DaemonClient.autostart()` reads exit 0 as "someone else got
            // there first" rather than "the binary is broken".
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
        // ONE sequence, shared with the app host: open, refuse a db written by
        // newer bits, back up when the ledger is behind, migrate, record the
        // start, bind. It THROWS rather than exiting so an app can show the
        // refusal. Watchers are owned by the Server's WatcherSupervisor and
        // rebuilt on CONFIG_SET / CREATE_INSTANCE via the post-commit fan-out.
        let services: KernelServices
        do {
            services = try KernelServices.bootWriter(
                consume token,
                personality: "headless",
                log: log
            )
        } catch {
            log("db bootstrap failed: \(error)")
            exit(1)
        }

        // --- signals ------------------------------------------------------
        // The headless shutdown ENDS IN exit(0): `KernelHostRole.takeOver`
        // sends SIGTERM and then polls for the lock, so this process must go
        // away rather than merely stop serving. The app host uses
        // `KernelServices.shutdown`, the same ordered teardown without the exit.
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
