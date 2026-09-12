import SwiftUI
import Observation

/// The app's shared service singletons in one container, injected by a single
/// modifier at every scene root — adding a service later is zero call-site
/// churn. Views keep their existing granular @Environment bindings
/// (GMCCEnvironment / FileTreeStore / DaemonConnectionModel / CatalogStore).
@Observable @MainActor
final class GMVibesServices {
    let env: GMCCEnvironment
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

    init() {
        env = GMCCEnvironment()
        fileTrees = FileTreeStore.shared
        daemon = DaemonConnectionModel()
        catalog = CatalogStore()
        checkout = CheckoutWatcher()
        diagramCatalog = DiagramCatalogStore()
        // The one wiring of the route() → checkout-state edge; both are
        // app-lifetime singletons, so no re-registration ever happens.
        daemon.checkoutSink = checkout
    }
}

extension View {
    /// Inject the shared GMCC services into a scene's root view in one call.
    func gmccEnv(_ services: GMVibesServices) -> some View {
        self
            .environment(services.env)
            .environment(services.fileTrees)
            .environment(services.daemon)
            .environment(services.catalog)
            .environment(services.checkout)
            .environment(services.diagramCatalog)
    }
}
