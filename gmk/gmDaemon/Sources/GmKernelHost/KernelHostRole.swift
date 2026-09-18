import Foundation
import GmDaemon
import GmDaemonSdk

/// What THIS process decided about itself, on its first line of life.
///
/// ## Not to be confused with `KernelRole`
///
/// `GmVibesCore.KernelRole` is a DISPLAY value: the role of whatever kernel
/// answered the socket, mapped from the wire's `writer_role` string, degrading
/// to `.unknown` rather than asserting. This is the ARBITRATION RESULT: what
/// this process is, decided locally, before anything could open the database.
///
/// They answer different questions and the names deliberately differ. A single
/// shared type would have to be either a lie on one side or an optional on
/// both.
///
/// ## The three outcomes, and why the third never fights
///
/// The distinction that decides everything is `Holder.bundlePath`, which
/// `KernelOwnership` documents as "nil means the holder is HEADLESS":
///
/// - **We won.** We are the writer. Boot the services.
/// - **A headless kernel holds it.** Take over: it is a fallback that exists
///   because hooks, SSH and CI cannot launch an application, and a person who
///   has just launched the app outranks it. SIGTERM, wait, re-acquire.
/// - **Another APP COPY holds it.** Degrade to client mode and never fight.
///   LaunchServices gives one instance per bundle PATH, so a debug build beside
///   the installed app is an ordinary daily occurrence — and two GUIs trading a
///   lock back and forth is worse than one of them being read-only.
///
/// Client mode is a DEGRADATION, never a refusal. A guard that refuses on the
/// daily path is a guard somebody deletes.
public enum KernelHostRole: ~Copyable {

    /// This process owns the database and is serving.
    case writer(KernelServices)

    /// Someone else owns it. We read over the socket like any other client.
    case client(holder: KernelOwnership.Holder)

    /// We won the lock and then could not open the database.
    ///
    /// A separate arm rather than folding into `.client`, because the two are
    /// opposite situations: in client mode somebody IS serving, and here nobody
    /// is. The case that reaches this is a schema written by newer bits, which
    /// `KernelWriter.start` refuses on purpose — and a refusal the UI can name
    /// is the entire value of refusing loudly.
    case failed(Error)

    /// Arbitrate. Call ONCE, before anything else can touch the database.
    ///
    /// - Parameter takeoverTimeout: how long to wait for a headless writer to
    ///   yield before settling for client mode.
    public static func arbitrate(
        takeoverTimeout: TimeInterval = 5,
        log: @escaping (String) -> Void = { _ in }
    ) -> KernelHostRole {
        switch acquireOnce(log: log) {
        case .some(let role):
            return role
        case .none:
            // Held by someone. Decide whether to take it.
            guard let holder = KernelOwnership.readHolder() else {
                log("lock is held but the pidfile is unreadable — client mode")
                return .client(
                    holder: KernelOwnership.Holder(
                        pid: 0, executablePath: "(unknown — pidfile unreadable)", bundlePath: nil))
            }

            if let bundle = holder.bundlePath {
                log("another app copy holds the store (pid \(holder.pid), \(bundle)) — client mode")
                return .client(holder: holder)
            }

            log("a headless kernel holds the store (pid \(holder.pid)) — taking over")
            return takeOver(from: holder, timeout: takeoverTimeout, log: log)
        }
    }

    /// One acquisition attempt. `nil` means somebody else has it.
    private static func acquireOnce(log: @escaping (String) -> Void) -> KernelHostRole? {
        let outcome: KernelOwnership.Outcome
        do {
            outcome = try KernelOwnership.acquire()
        } catch {
            return .failed(error)
        }
        switch consume outcome {
        case .heldBy:
            return nil
        case .acquired(let token):
            do {
                return .writer(try KernelServices.bootWriter(consume token, log: log))
            } catch {
                // We hold the lock and cannot use it. Say so; do not pretend to
                // be a client, because nothing is serving.
                log("won the lock but could not open the database: \(error)")
                return .failed(error)
            }
        }
    }

    /// SIGTERM a headless holder and wait for the lock.
    ///
    /// SIGTERM and never SIGKILL. `Boot.swift` installs a signal source that
    /// runs the ordered shutdown — checkpoint, close, unlink — so the polite
    /// signal is the entire reason this is safe. Escalating would throw away
    /// the thing that makes it safe and leave a WAL to recover.
    ///
    /// The timeout falls back to client mode rather than retrying harder. A
    /// headless kernel that will not yield in five seconds is busy with
    /// something, and killing it is not an improvement.
    private static func takeOver(
        from holder: KernelOwnership.Holder,
        timeout: TimeInterval,
        log: @escaping (String) -> Void
    ) -> KernelHostRole {
        guard holder.pid > 0, kill(holder.pid, SIGTERM) == 0 else {
            log("could not signal pid \(holder.pid): \(String(cString: strerror(errno))) — client mode")
            return .client(holder: holder)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(100_000)  // 100ms
            if let role = acquireOnce(log: log) {
                log("took over from headless pid \(holder.pid)")
                return role
            }
        }

        log("headless pid \(holder.pid) did not yield within \(timeout)s — client mode")
        return .client(holder: holder)
    }
}
