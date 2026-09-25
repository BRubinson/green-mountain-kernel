import Foundation

/// The ARBITRATION RESULT: what THIS process is, decided locally before DB open.
///
/// Distinct from `GmVibesCore.KernelRole` (DISPLAY value for socket responder).
/// A lock held by anyone else means another app copy or a test host owns the
/// store; the app never fights it.
enum KernelHostRole: ~Copyable {

    /// This process owns the database and is serving.
    case writer(KernelServices)

    /// Someone else owns it. The app says who and quits.
    case client(holder: KernelOwnership.Holder)

    /// We won the lock and then could not open the database. Separate from
    /// `.client`, where somebody IS serving and here nobody is. The case that
    /// reaches it is a schema written by newer bits, which `KernelWriter.start`
    /// refuses loudly so the UI can name the refusal.
    case failed(Error)

    /// Determines the kernel host role: writer, client, or failed.
    ///
    /// Call ONCE, before anything else can touch the database. Attempts the lock
    /// once; a held lock is reported with its holder, never taken over.
    ///
    /// - Parameter log: A closure called with diagnostic messages; defaults to ignoring messages.
    /// - Returns: A `KernelHostRole.writer` if lock acquired, `.client` if another process holds it, or `.failed` if an error occurs.
    static func arbitrate(log: @escaping (String) -> Void = { _ in }) -> KernelHostRole {
        let outcome: KernelOwnership.Outcome
        do {
            outcome = try KernelOwnership.acquire()
        } catch {
            return .failed(error)
        }
        switch consume outcome {
        case .heldBy:
            guard let holder = KernelOwnership.readHolder() else {
                log("lock is held but the pidfile is unreadable")
                return .client(
                    holder: KernelOwnership.Holder(
                        pid: 0,
                        executablePath: "(unknown — pidfile unreadable)",
                        bundlePath: nil
                    )
                )
            }
            log("pid \(holder.pid) holds the store (\(holder.bundlePath ?? holder.executablePath))")
            return .client(holder: holder)
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
}
