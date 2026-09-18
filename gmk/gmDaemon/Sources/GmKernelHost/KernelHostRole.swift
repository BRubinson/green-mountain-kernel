import Foundation
import GmDaemon
import GmDaemonSdk

/// The ARBITRATION RESULT: what THIS process is, decided locally before
/// anything could open the database. Distinct from `GmVibesCore.KernelRole`,
/// which is a DISPLAY value for whichever kernel answered the socket.
///
/// `Holder.bundlePath` decides the loser's branch: nil means a HEADLESS holder,
/// which a person's freshly launched app outranks, so take it over; a bundle
/// path means another APP COPY, and two GUIs trading a lock is worse than one
/// being read-only. Client mode is a DEGRADATION, never a refusal.
public enum KernelHostRole: ~Copyable {

    /// This process owns the database and is serving.
    case writer(KernelServices)

    /// Someone else owns it. We read over the socket like any other client.
    case client(holder: KernelOwnership.Holder)

    /// We won the lock and then could not open the database. Separate from
    /// `.client`, where somebody IS serving and here nobody is. The case that
    /// reaches it is a schema written by newer bits, which `KernelWriter.start`
    /// refuses loudly so the UI can name the refusal.
    case failed(Error)

    /// Arbitrate. Call ONCE, before anything else can touch the database;
    /// `takeoverTimeout` bounds the wait for a headless writer to yield.
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
                        pid: 0,
                        executablePath: "(unknown — pidfile unreadable)",
                        bundlePath: nil
                    )
                )
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

    /// SIGTERM a headless holder and wait for the lock. Never SIGKILL: the
    /// polite signal is what runs `Boot.swift`'s ordered shutdown — checkpoint,
    /// close, unlink — and is the entire reason this is safe. A timeout falls
    /// back to client mode rather than escalating.
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
