import AppKit
import Observation
import SwiftUI

/// The app's shared service singletons in one container, injected by a single
/// modifier at every scene root — adding a service later is zero call-site
/// churn.
///
/// The kernel is hosted in this process; a second app copy alerts and quits
/// before it can touch the database. Views keep their existing granular
/// @Environment bindings (GMVibesEnvironment / FileTreeStore /
/// DaemonConnectionModel / CatalogStore).
@Observable @MainActor
final class GMVibesServices {
    let env: GMVibesEnvironment
    let fileTrees: FileTreeStore
    let daemon: DaemonConnectionModel
    let catalog: CatalogStore
    /// Checked-out session per instance (CHECKOUT_CHANGE push edge +
    /// daemon-side INSTANCE_CURRENT_SESSION resolution).
    let checkout: CheckoutWatcher
    /// Tier-scoped diagram lists (DIAGRAM_LIST) + the row-level writes.
    ///
    /// App-lifetime, like CatalogStore: the project rail, the session pane
    /// and every prompt row read one store.
    let diagramCatalog: DiagramCatalogStore
    let launchColors: LaunchColorRegistry

    /// THE KERNEL, hosted in this process.
    ///
    /// nil only when we won the lock and could not open the database. Non-nil
    /// means we took the flock, opened and migrated the database and are serving.
    private let kernel: KernelServices?

    /// Set when we won the lock and then could not open the database — a
    /// schema written by newer bits is the case that reaches this.
    ///
    /// Here NOBODY is serving.
    private let kernelFailure: Error?

    /// Our row in the store's post-commit subscriber table, released on
    /// shutdown.
    ///
    /// Writer mode only.
    private var kernelEventToken: UUID?

    /// Creates the services container, hosting the kernel or quitting when another copy holds it.
    ///
    /// A losing copy alerts and exits before touching the database; a lock won
    /// with a database that fails to open is stored, not thrown.
    init() {
        // ARBITRATION IS THE FIRST THING THAT HAPPENS, before any stored
        // property that could reach the database. `KernelOwnership.acquire`
        // takes the flock before anything can open the store, and a losing
        // process cannot open it at all — there is no expression that does.
        var services: KernelServices?
        var failure: Error?
        switch KernelHostRole.arbitrate(log: { NSLog("[gm_kernel] %@", $0) }) {
        case .writer(let hosted):
            services = hosted
        case .client(let who):
            // Never fight the holder and never touch its database: say who owns it and leave.
            let alert = NSAlert()
            alert.messageText = "GMVibes is already running"
            alert.informativeText =
                "The database is owned by pid \(who.pid) (\(who.bundlePath ?? who.executablePath)). "
                + "Use that copy of GMVibes."
            alert.runModal()
            exit(0)
        case .failed(let error):
            failure = error
        }
        kernel = services
        kernelFailure = failure

        env = GMVibesEnvironment()
        fileTrees = FileTreeStore.shared
        daemon = DaemonConnectionModel()
        catalog = CatalogStore()
        checkout = CheckoutWatcher()
        diagramCatalog = DiagramCatalogStore()
        launchColors = LaunchColorRegistry()
        // The one wiring of the route() → checkout-state edge; both are
        // app-lifetime singletons, so no re-registration ever happens.
        daemon.checkoutSink = checkout

        // WRITER MODE: swap the transport and take the events in-process. Both halves have
        // to happen together — SUBSCRIBE is a socket verb, so adopting the verb caller alone
        // leaves the UI reading a store it never hears change from.
        if let kernel {
            // The health loop must not gate on the on-disk binary when the
            // kernel is this very process. Set synchronously, in the same
            // MainActor scope that created the model, so the autorun loop's
            // first turn already sees it.
            daemon.hostsKernelInProcess = true
            // The store and the status closure are Sendable; the kernel object is not,
            // so only those two halves are handed to the actor.
            let store = kernel.store
            let status = kernel.statusBuilder
            Task {
                await GMCCDaemonService.shared.install(store: store, status: status)
                self.daemon.markKernelHosted()
            }
            kernelEventToken = kernel.store.subscribeToEvents { [weak self] event in
                // FAN-OUT RUNS ON GRDB'S WRITER THREAD, inside the commit hook. Hand off
                // immediately and touch nothing here: blocking stalls the single writer for
                // every client, and calling back into the store deadlocks. The commit has
                // already landed, so this hop is outside the transaction boundary.
                let notification = event.notification
                Task { @MainActor [weak self] in
                    self?.daemon.routeInProcess(notification)
                }
            }
        } else if let failure {
            Task { await GMCCDaemonService.shared.install(failure: failure) }
            daemon.markKernelFailed(String(describing: failure))
        }
    }

    // MARK: - The app target's window onto the kernel
    //
    // A FACADE, not `public let daemon`. Exposing `DaemonConnectionModel` would make an
    // entire observable model part of this module's public surface to serve four scalars.
    // These properties are the whole of what `GMVibesApp` needs.

    /// Vitals as the in-process kernel last sampled them, or nil before the first sample.
    ///
    /// Shaped for `KernelVitals(report:)`.
    var vitalsReport: KernelVitalsReport? { daemon.vitals }

    /// Whether this process serves the database.
    ///
    /// `.writer` when the kernel is hosted here, `.unknown` when the lock was
    /// won but the database failed to open.
    var kernelRole: KernelRole { kernel != nil ? .writer : .unknown }

    /// True when this process owns the database.
    ///
    /// The termination path needs to know whether there is a kernel to
    /// stop at all.
    var isKernelWriter: Bool { kernel != nil }

    /// Stop the kernel, in order, before the process goes away.
    ///
    /// A no-op when the database failed to open: there is no kernel to stop.
    ///
    /// The dirty-draft flush is NOT passed in here. The ordering is flush (awaited, bounded)
    /// and THEN stop the kernel, and `GMVibesAppDelegate.applicationShouldTerminate` owns
    /// that deadline — a synchronous closure here could not have awaited it.
    func shutdownKernel() {
        guard let kernel else { return }
        if let token = kernelEventToken {
            kernel.store.unsubscribeFromEvents(token)
            kernelEventToken = nil
        }
        kernel.shutdown()
    }

    /// The wire protocol version this binary speaks.
    var protocolVersion: Int? { GmWireProtocol.version }

    /// The commit this binary was built from.
    var buildSha: String? { BuildInfo.sha }
}

extension View {
    /// Injects the shared services into a view hierarchy.
    /// - Parameter services: The services container.
    /// - Returns: The modified view with all services in the environment.
    func gmEnv(_ services: GMVibesServices) -> some View {
        self
            .environment(services.env)
            .environment(services.fileTrees)
            .environment(services.daemon)
            .environment(services.catalog)
            .environment(services.checkout)
            .environment(services.diagramCatalog)
            .environment(services.launchColors)
    }
}
