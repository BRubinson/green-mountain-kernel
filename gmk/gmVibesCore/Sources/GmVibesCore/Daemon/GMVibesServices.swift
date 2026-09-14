import AppKit
import GmDaemonSdk
import GmKernelHost
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
        // The one wiring of the route() → checkout-state edge; both are
        // app-lifetime singletons, so no re-registration ever happens.
        daemon.checkoutSink = checkout

        // WRITER MODE: swap the transport and take the events in-process.
        //
        // Both halves have to happen together. Adopting the verb caller without
        // subscribing would leave the UI reading a store it never hears change
        // from, because SUBSCRIBE is a socket verb and this process no longer
        // dials the socket.
        if let kernel {
            Task { await GMCCDaemonService.shared.adopt(inProcess: kernel.verbCaller) }
            kernelEventToken = kernel.store.subscribeToEvents { [weak self] event in
                // FAN-OUT RUNS ON GRDB'S WRITER THREAD, inside the commit hook.
                // Hand off immediately and touch nothing here: blocking stalls
                // the single writer for every client on the machine, and calling
                // back into the store deadlocks.
                //
                // This hop is NOT the thread hop the transaction boundary
                // forbids — the commit has already landed, so we are past the
                // boundary rather than inside it.
                let notification = event.notification
                Task { @MainActor [weak self] in
                    self?.daemon.routeInProcess(notification)
                }
            }
        }
    }

    // MARK: - The app target's window onto the kernel
    //
    // DELIBERATELY A FACADE, not `public let daemon`. The app entry point needs
    // four scalars off the latest ping; exposing `DaemonConnectionModel` to hand
    // them over would make an entire observable model — and everything its API
    // touches — part of this module's public surface, to serve a handful of
    // reads. These four properties are the whole of what `GMVibesApp` needs, and
    // they keep the ping-to-view-model mapping in here, where the rest of it
    // already lives.

    /// Vitals as the answering kernel last reported them, or nil before the
    /// first ping. Shaped for `KernelVitals(report:)`.
    public var vitalsReport: KernelVitalsReport? {
        guard let ping = daemon.ping else { return nil }
        return KernelVitalsReport(
            uptimeSeconds: ping.uptimeSeconds,
            residentMemoryBytes: ping.residentMemoryBytes,
            cpuPercent: ping.cpuPercent)
    }

    /// Who holds the database.
    ///
    /// WE ANSWER LOCALLY WHEN WE KNOW. Arbitration already settled this before
    /// the first ping existed, and waiting for the wire to tell us what we
    /// decided ourselves would leave the menu bar reading `.unknown` for the
    /// first second of its own kernel's life. The role row is the mitigation for
    /// running as a client, and a mitigation nobody can see is cosmetic.
    ///
    /// In CLIENT mode the wire is still the authority — only the holder can
    /// report on itself — and the existing mapping is unchanged. `writerRole`
    /// and `writerBundlePath` are additive optionals, so a kernel predating them
    /// answers nil and this reads `.unknown`.
    ///
    /// This adds NO connection and NO polling cadence. It short-circuits one
    /// value; `DaemonConnectionModel` still runs the single health watchdog.
    public var kernelRole: KernelRole {
        if kernel != nil { return .writer }
        if let kernelHolder {
            return .client(
                holderPid: kernelHolder.pid,
                bundlePath: kernelHolder.bundlePath)
        }
        guard let ping = daemon.ping else { return .unknown }
        return KernelRole(
            writerRole: ping.writerRole,
            holderPid: ping.daemonPid,
            bundlePath: ping.writerBundlePath)
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
    /// A NO-OP IN CLIENT MODE, deliberately: a client holds no lock and owns no
    /// database, and quitting it must not disturb the kernel that does.
    ///
    /// ## The draft flush is NOT passed in here, and that is the right shape
    ///
    /// The ordering problem this had to solve was that the app's dirty-edit
    /// flush travelled THROUGH THE SOCKET — which cannot work once both ends are
    /// one process and the listener has been cancelled. That is fixed by the
    /// transport swap, not by this function: `GMCCDaemonService` now reaches the
    /// verb layer directly, so the flush is an ordinary in-process write.
    ///
    /// Which leaves the simple ordering: flush (awaited, bounded) and THEN stop
    /// the kernel. `GMVibesAppDelegate.applicationShouldTerminate` already owns
    /// exactly that deadline, so the flush stays there rather than being smuggled
    /// into a synchronous closure it could not have awaited anyway.
    ///
    /// `KernelServices.shutdown(beforeClose:)` still takes the hook — a
    /// last-write-before-close is a real need — this caller simply does not have
    /// one left.
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
    }
}
