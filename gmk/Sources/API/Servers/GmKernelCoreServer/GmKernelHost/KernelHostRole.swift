import Foundation

/// The ARBITRATION RESULT: what THIS process is, decided locally before DB open.
///
/// Distinct from `GmVibesCore.KernelRole` (DISPLAY value for socket responder).
/// `Holder.bundlePath` decides loser's branch: nil = HEADLESS (outranked by
/// user's app launch); bundle path = another APP COPY (two GUIs trading lock is
/// worse than one read-only). Client mode is a DEGRADATION, not refusal.
enum KernelHostRole: ~Copyable {

    /// This process owns the database and is serving.
    case writer(KernelServices)

    /// Someone else owns it. We read over the socket like any other client.
    case client(holder: KernelOwnership.Holder)

    /// We won the lock and then could not open the database. Separate from
    /// `.client`, where somebody IS serving and here nobody is. The case that
    /// reaches it is a schema written by newer bits, which `KernelWriter.start`
    /// refuses loudly so the UI can name the refusal.
    case failed(Error)

    /// Arbitrate.
    ///
    /// Call ONCE, before anything else can touch the database; `takeoverTimeout` bounds the wait for a headless writer
    /// to yield.
    /// Determines the kernel host role: writer, client, or failed.
    ///
    /// Attempts to acquire the lock; if held by another process, decides whether
    /// to take over (headless) or operate as a client (app).
    ///
    /// - Parameters:
    ///   - takeoverTimeout: Maximum time to wait for a headless holder to shut down; defaults to 5 seconds.
    ///   - log: A closure called with diagnostic messages; defaults to ignoring messages.
    /// - Returns: A `KernelHostRole.writer` if lock acquired, `.client` if another process holds it, or `.failed` if an error occurs.
    static func arbitrate(
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

    /// Attempts to acquire the lock once without retrying or taking over.
    ///
    /// - Parameter log: A closure called with diagnostic messages.
    /// - Returns: A role if acquired or failed; nil if someone else holds the lock.
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

    /// Takes over from a headless holder by sending SIGTERM and waiting for the lock.
    ///
    /// Never sends SIGKILL; the polite signal runs `Boot.swift`'s ordered shutdown
    /// (checkpoint, close, unlink) which makes takeover safe. A timeout falls back
    /// to client mode rather than escalating.
    ///
    /// - Parameters:
    ///   - holder: The current lock holder to signal and wait for.
    ///   - timeout: Maximum time to wait for the holder to release the lock.
    ///   - log: A closure called with diagnostic messages.
    /// - Returns: A `KernelHostRole.writer` if takeover succeeds, or `.client` if timeout or signal fails.
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
