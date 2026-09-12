import SwiftUI

/// The BaseScreen shell: the ONLY navigation containers in the app.
///
/// Every route mounts exactly one container through this type — a
/// `NavigationStack` for plain routes, a `NavigationSplitView` when a sidebar
/// is supplied — so `.navigationTitle` / `.navigationSubtitle` / `.searchable`
/// / `.toolbar(placement: .primaryAction)` resolve to the SAME titlebar
/// geometry on every screen. Those native modifiers ARE the overrideable
/// per-screen seams; there is deliberately no parallel preference pipeline.
/// (The per-route container divergence this replaces is why `.navigation`
/// placement used to land in different physical spots per route.)
///
/// House rules that ride on this shape:
/// - `GlobalToolbarGroup` stays window-level with `.navigation` placement.
/// - The split shape is a real `NavigationSplitView` (never `HSplitView`,
///   which leaks toolbar items and resets pane state) and its columns own
///   their toolbar/title/`.task` lifecycles.
/// - No screen outside this file declares `NavigationStack` or
///   `NavigationSplitView` (modal sheets excepted).
struct ScreenScaffold<Sidebar: View, Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Sidebar.self == EmptyView.self {
            NavigationStack {
                decorated
            }
        } else {
            NavigationSplitView {
                sidebar()
            } detail: {
                decorated
            }
        }
    }

    @ViewBuilder
    private var decorated: some View {
        if let title {
            content()
                .navigationTitle(title)
                .navigationSubtitle(subtitle ?? "")
        } else {
            content()   // the screen declares its own title/subtitle inside
        }
    }
}

extension ScreenScaffold where Sidebar == EmptyView {
    /// Plain shape: a `NavigationStack` hosting the content.
    init(title: String? = nil, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.sidebar = { EmptyView() }
        self.content = content
    }
}
