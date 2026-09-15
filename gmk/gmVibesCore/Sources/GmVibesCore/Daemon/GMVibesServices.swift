import SwiftUI
import Observation

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

    public init() {
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

    /// Who holds the database, as the answering kernel reports it.
    ///
    /// `writerRole` and `writerBundlePath` are additive optionals, so a kernel
    /// predating them answers nil and this reads `.unknown` — correct rather
    /// than merely safe, because this app does not yet host the writer and
    /// claiming either role would be a lie.
    public var kernelRole: KernelRole {
        guard let ping = daemon.ping else { return .unknown }
        return KernelRole(
            writerRole: ping.writerRole,
            holderPid: ping.daemonPid,
            bundlePath: ping.writerBundlePath)
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
