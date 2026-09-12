import SwiftUI

/// Sliding global navigation rail. Deliberately NOT a `NavigationSplitView`
/// sidebar: the session screen owns one of those for its prompt navigator, and
/// nesting two split views fights on macOS. Collapses after every click.
struct GlobalNavRail: View {
    @Environment(WindowNav.self) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            railButton("Home", systemImage: "house") { nav.home() }
            railButton("Projects", systemImage: "folder") { nav.go(.projects) }
            railButton("Knowledge Bites", systemImage: "lightbulb") { nav.go(.kbites) }
            railButton("Search", systemImage: "magnifyingglass") { nav.go(.search(SearchSeed())) }
            Spacer()
        }
        .padding(10)
        .frame(width: 200, alignment: .leading)
        .background(.regularMaterial)
    }

    private func railButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}
