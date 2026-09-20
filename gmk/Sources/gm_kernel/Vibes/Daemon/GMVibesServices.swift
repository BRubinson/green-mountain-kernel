import AppKit
import Observation
import SwiftUI

/// The app's shared service singletons in one container, injected by a single
/// modifier at every scene root — adding a service later is zero call-site
/// churn. Views keep their existing granular @Environment bindings
/// (GMVibesEnvironment / FileTreeStore / DaemonConnectionModel / CatalogStore).
@Observable @MainActor
public final class GMVibesServices {
    let env: GMVibesEnvironment
    let fileTrees: FileTreeStore
    let daemon: DaemonConnectionModel
    let catalog: CatalogStore
    /// Checked-out session per instance (CHECKOUT_CHANGE push edge +
    /// daemon-side INSTANCE_CURRENT_SESSION resolution).
    let checkout: CheckoutWatcher
    /// Tier-scoped diagram lists (DIAGRAM_LIST) + the row-level writes.
    /// App-lifetime, like CatalogStore: the project rail, the session pane
    /// and every prompt row read one store.
    let diagramCatalog: DiagramCatalogStore
    let launchColors: LaunchColorRegistry

    /// THE KERNEL, when this process is the one holding it.
    ///
    /// nil means client mode: another kernel owns the store and we read over the
    /// socket, exactly as this app always did. Non-nil means we took the flock,
    /// opened the database, migrated it and are serving — and every verb call
    /// below skips the socket entirely.
    private let kernel: KernelServices?

    /// The holder, when we are NOT it. Drives the menu bar's client-mode row.
    private let kernelHolder: KernelOwnership.Holder?

    /// Set when we won the lock and then could not open the database — a schema
    /// written by newer bits is the case that reaches this. Distinct from client
    /// mode because here NOBODY is serving.
    private let kernelFailure: Error?

    /// Our row in the store's post-commit subscriber table, released on
    /// shutdown. Writer mode only.
    private var kernelEventToken: UUID?

    public init() {
        // ARBITRATION IS THE FIRST THING THAT HAPPENS, before any stored
        // property that could reach the database. `KernelOwnership.acquire`
        // takes the flock before anything can open the store, and a losing
        // process cannot open it at all — there is no expression that does.
        var services: KernelServices?
        var holder: KernelOwnership.Holder?
        var failure: Error?
        switch KernelHostRole.arbitrate(log: { NSLog("[gm_kernel] %@", $0) }) {
        case .writer(let hosted):
            services = hosted
        case .client(let who):
            holder = who
        case .failed(let error):
            failure = error
        }
        kernel = services
        kernelHolder = holder
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
            Task { await GMCCDaemonService.shared.adopt(inProcess: kernel.verbCaller) }
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
        }
    }

    // MARK: - The app target's window onto the kernel
    //
    // A FACADE, not `public let daemon`. Exposing `DaemonConnectionModel` would make an
    // entire observable model part of this module's public surface to serve four scalars
    // off the latest ping. These properties are the whole of what `GMVibesApp` needs.

    /// Vitals as the answering kernel last reported them, or nil before the
    /// first ping. Shaped for `KernelVitals(report:)`.
    public var vitalsReport: KernelVitalsReport? {
        guard let ping = daemon.ping else { return nil }
        return KernelVitalsReport(
            uptimeSeconds: ping.uptimeSeconds,
            residentMemoryBytes: ping.residentMemoryBytes,
            cpuPercent: ping.cpuPercent
        )
    }

    /// Who holds the database. Answered locally when arbitration already knows, so the menu
    /// bar does not read `.unknown` for the first second of its own kernel's life.
    ///
    /// In CLIENT mode the wire is the authority, because only the holder can report on
    /// itself. `writerRole` and `writerBundlePath` are additive optionals, so a kernel
    /// without them answers nil and this reads `.unknown`. No extra connection and no
    /// polling: `DaemonConnectionModel` still runs the single health watchdog.
    public var kernelRole: KernelRole {
        if kernel != nil { return .writer }
        if let kernelHolder {
            return .client(
                holderPid: kernelHolder.pid,
                bundlePath: kernelHolder.bundlePath
            )
        }
        guard let ping = daemon.ping else { return .unknown }
        return KernelRole(
            writerRole: ping.writerRole,
            holderPid: ping.daemonPid,
            bundlePath: ping.writerBundlePath
        )
    }

    /// Bring the kernel that actually owns the store to the front.
    ///
    /// nil unless we are a client of ANOTHER APP COPY with a known bundle —
    /// there is nothing to activate when we are the writer, and a headless
    /// holder has no window to raise. `KernelMenuBarContent` renders the row
    /// only when this is non-nil, so the absent case is already handled there
    /// as an absent row rather than a disabled one.
    public var activateHolder: (() -> Void)? {
        guard let kernelHolder, let bundlePath = kernelHolder.bundlePath else { return nil }
        let pid = kernelHolder.pid
        return {
            // By pid first: it names the exact process holding the lock. The
            // bundle path is the fallback for a holder that has gone away
            // between the pidfile read and the click, where launching the app
            // is the useful thing to do anyway.
            if let running = NSRunningApplication(processIdentifier: pid) {
                running.activate(options: [.activateAllWindows])
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: bundlePath))
            }
        }
    }

    /// True when this process owns the database. The termination path needs to
    /// know whether there is a kernel to stop at all.
    public var isKernelWriter: Bool { kernel != nil }

    /// Stop the kernel, in order, before the process goes away.
    ///
    /// A no-op in client mode: a client holds no lock and owns no database, and quitting it
    /// must not disturb the kernel that does.
    ///
    /// The dirty-draft flush is NOT passed in here. The ordering is flush (awaited, bounded)
    /// and THEN stop the kernel, and `GMVibesAppDelegate.applicationShouldTerminate` owns
    /// that deadline — a synchronous closure here could not have awaited it.
    public func shutdownKernel() {
        guard let kernel else { return }
        if let token = kernelEventToken {
            kernel.store.unsubscribeFromEvents(token)
            kernelEventToken = nil
        }
        kernel.shutdown()
    }

    public var protocolVersion: Int? { daemon.ping?.protocolVersion }
    public var buildSha: String? { daemon.ping?.buildSha }
}

extension View {
    /// Inject the shared GMCC services into a scene's root view in one call.
    public func gmEnv(_ services: GMVibesServices) -> some View {
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
