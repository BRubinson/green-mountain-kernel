import Foundation
import GMCCDaemonKit

/// Owns both watchers and the ONE recompute path serving A3 (ckfs re-rooting)
/// and A8 (instance-set churn). It recomputes both watched sets from
/// committed db state and pushes them down; both pushes are idempotent, so a
/// rebuild triggered by an irrelevant change costs two comparisons.
///
/// MUST be called on the SERVER queue — rebuild performs dbQueue reads, and
/// calling it from inside the event sink (which fires on the DATABASE's queue
/// while the issuing write turn is still unwinding) would deadlock.
final class WatcherSupervisor: @unchecked Sendable {
    private let store: Store
    private let memory: MemoryWatcher
    private let checkout: CheckoutWatcher
    private var bootLogged = false

    init(store: Store, memory: MemoryWatcher, checkout: CheckoutWatcher) {
        self.store = store
        self.memory = memory
        self.checkout = checkout
    }

    /// Recompute both watched sets from committed db state.
    func rebuild() {
        let ckfs = (try? store.configValue(.ckfsRoot)).flatMap { $0 }
        let watchableCkfs = ckfs.flatMap {
            FileManager.default.fileExists(atPath: $0) ? $0 : nil
        }
        memory.setRoot(watchableCkfs)

        let instances = (try? store.listInstances(
            InstanceListRequest(projectUuid: nil)).instances) ?? []
        // Instances whose path no longer exists drop out; they rejoin on the
        // next rebuild if the repo reappears. KNOWN LIMIT: a repo cloned back
        // between rebuilds is not re-watched until the next instance creation
        // or config write — SESSION_RESOLVE remains the authority for state.
        let roots = instances.compactMap { instance -> (String, String, String)? in
            GitHead.gitDirectory(repoRoot: instance.absoluteFileSystemPath).map {
                (instance.uuid, instance.absoluteFileSystemPath, $0)
            }
        }
        checkout.setRoots(roots.map { (instanceUuid: $0.0, repoRoot: $0.1, gitDir: $0.2) })

        if !bootLogged {
            bootLogged = true
            print("[\(Store.isoNow())] watchers: memory "
                + (watchableCkfs.map { "on \($0)" } ?? "disabled (no ckfs_root configured or path missing)")
                + ", checkout on \(roots.count) instance repo(s)")
            fflush(stdout)
        }
    }
}
