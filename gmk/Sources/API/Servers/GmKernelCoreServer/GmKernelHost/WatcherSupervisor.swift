import Foundation

/// Owns both watchers and the ONE recompute path serving A3 (gmfs re-rooting)
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
    private let checkout: CheckoutFSEventLane
    private var bootLogged = false

    init(store: Store, memory: MemoryWatcher, checkout: CheckoutFSEventLane) {
        self.store = store
        self.memory = memory
        self.checkout = checkout
    }

    /// Recompute both watched sets from committed db state.
    func rebuild() {
        let gmfs = (try? store.configValue(.gmFsRoot)).flatMap(\.self)
        let watchableGmfs = gmfs.flatMap {
            FileManager.default.fileExists(atPath: $0) ? $0 : nil
        }
        memory.setRoot(watchableGmfs)

        let instances =
            (try? store.listInstances(
                InstanceListRequest(projectUuid: nil)
            )
            .instances) ?? []
        // Instances whose path is gone drop out and rejoin on a later rebuild.
        // KNOWN LIMIT: a repo cloned back between rebuilds is not re-watched
        // until the next instance creation or config write; SESSION_RESOLVE
        // remains the authority for state.
        let roots = instances.compactMap { instance -> (String, String, String)? in
            GitHead.gitDirectory(repoRoot: instance.absoluteFileSystemPath)
                .map {
                    (instance.uuid, instance.absoluteFileSystemPath, $0)
                }
        }
        checkout.setRoots(roots.map { (instanceUuid: $0.0, repoRoot: $0.1, gitDir: $0.2) })

        if !bootLogged {
            bootLogged = true
            print(
                "[\(Store.isoNow())] watchers: memory "
                    + (watchableGmfs.map { "on \($0)" } ?? "disabled (no gmfs_root configured or path missing)")
                    + ", checkout on \(roots.count) instance repo(s)"
            )
            fflush(stdout)
        }
    }
}
