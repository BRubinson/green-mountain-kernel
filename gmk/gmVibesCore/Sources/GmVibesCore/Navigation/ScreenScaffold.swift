import SwiftUI

/// The BaseScreen shell: the ONLY navigation containers in the app.
///
/// Every route mounts exactly one container through this type, so `.navigationTitle`,
/// `.searchable` and `.toolbar` resolve to the same titlebar geometry on every screen. Those
/// native modifiers ARE the per-screen seams; there is no parallel preference pipeline.
/// `GlobalToolbarGroup` stays window-level with `.navigation` placement. The split shape is a
/// real `NavigationSplitView`, never `HSplitView`, which leaks toolbar items and resets pane
/// state. No screen outside this file declares either container, modal sheets excepted.
struct ScreenScaffold<Sidebar: View, Content: View>: View {
    var title: String?
    var subtitle: String?
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
            content()  // the screen declares its own title/subtitle inside
        }
    }
}

extension ScreenScaffold where Sidebar == EmptyView {
    /// Plain shape: a `NavigationStack` hosting the content.
    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sidebar = { EmptyView() }
        self.content = content
    }
}
