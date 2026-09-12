import Foundation
import GMCCDaemonKit

// gmcc_daemon — the single writer. Boot order:
//   1. ensure ~/gmcc/ exists
//   2. pidfile flock — a second instance exits 0 immediately (makes client
//      autostart races harmless)
//   3. redirect stdout/stderr → ~/gmcc/daemon.log
//   4. open + migrate the db, record DAEMON_START
//   5. bind the unix socket, serve, dispatchMain()

do {
    try Paths.ensureRuntimeDirs()
} catch {
    FileHandle.standardError.write(Data("[gmcc_daemon] cannot create ~/gmcc: \(error)\n".utf8))
    exit(1)
}

// --- pidfile flock (keep the fd open for the process's lifetime; the lock
// auto-releases on exit, so a crashed daemon never wedges the pidfile) -------
let pidFd = open(Paths.pidfile.path, O_CREAT | O_RDWR, 0o644)
guard pidFd >= 0 else {
    FileHandle.standardError.write(Data("[gmcc_daemon] cannot open pidfile\n".utf8))
    exit(1)
}
guard flock(pidFd, LOCK_EX | LOCK_NB) == 0 else {
    // Another daemon owns the lock — we're a redundant autostart. Not an error.
    exit(0)
}
ftruncate(pidFd, 0)
let pidLine = "\(getpid())\n"
_ = pidLine.withCString { write(pidFd, $0, strlen($0)) }

// --- log redirection --------------------------------------------------------
let logFd = open(Paths.log.path, O_CREAT | O_WRONLY | O_APPEND, 0o644)
if logFd >= 0 {
    dup2(logFd, STDOUT_FILENO)
    dup2(logFd, STDERR_FILENO)
}

func log(_ message: String) {
    print("[\(Store.isoNow())] \(message)")
    fflush(stdout)
}

// --- db ---------------------------------------------------------------------
let store: Store
do {
    store = try Store(path: Paths.db.path)
    try store.migrate()
    try store.recordDaemonStart()
} catch {
    log("db bootstrap failed: \(error)")
    exit(1)
}

// --- server -----------------------------------------------------------------
let server: Server
do {
    server = try Server(store: store)
} catch {
    log("cannot bind \(Paths.socket.path): \(error)")
    exit(1)
}
server.start()
log("daemon pid \(getpid()) protocol v\(GMCCWireProtocol.version) listening at \(Paths.socket.path)")
// Watchers (memory + checkout) are owned by the Server's WatcherSupervisor,
// built inside server.start() and rebuilt on CONFIG_SET / CREATE_INSTANCE via
// the post-commit event sink — no ad-hoc boot-time watcher block anymore.
// The supervisor's first rebuild logs the watched state.

// --- signals ----------------------------------------------------------------
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    log("SIGTERM — shutting down")
    server.shutdown()
}
sigtermSource.resume()
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    log("SIGINT — shutting down")
    server.shutdown()
}
sigintSource.resume()

dispatchMain()
