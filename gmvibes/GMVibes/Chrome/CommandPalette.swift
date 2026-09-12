import SwiftUI
import GMCCDaemonKit

/// App-wide search popup (cmd+K). Floats centered over all content; Esc or a
/// click outside dismisses. Global full-text SEARCH over the GMCC database
/// with prompt-level deep-linking; "Show all results" hands the query off to
/// the dedicated search screen for scoping and kind filters.
struct CommandPalette: View {
    @Environment(WindowNav.self) private var nav
    @Environment(CatalogStore.self) private var catalog

    @State private var query = ""
    @State private var selection: String?
    @State private var model = DaemonSearchModel(limit: 20)   // overlay: top hits only
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Click-outside scrim.
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { nav.paletteOpen = false }

            VStack(spacing: 10) {
                CapsuleSearchField(
                    prompt: "Search prompts, clarifications, architecture…",
                    text: $query,
                    focus: $focused
                )
                .onChange(of: query) { _, new in
                    model.schedule(query: new)   // global scope: the palette is the fast jump
                    selection = nil
                }
                .onSubmit { openSelectedOrFirst() }

                SearchResultsList(
                    hits: model.hits,
                    searched: model.searched,
                    errorText: model.errorText,
                    selection: $selection,
                    idleDescription: "Full-text search across every session in the GMCC database.",
                    destination: { catalog.sessionWindowID(forSessionUuid: $0.sessionUuid) },
                    onOpen: open
                )
                .frame(height: 320)

                if !model.hits.isEmpty {
                    Button("Show all results in Search") {
                        let seed = SearchSeed(query: query)
                        nav.paletteOpen = false
                        Task { @MainActor in nav.go(.search(seed)) }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(18)
            .frame(width: 560)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            // The field owns focus, so the List never sees arrow keys — drive
            // selection from the container instead of fighting for first responder.
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }

            // Esc dismissal that needs no focus plumbing: .onExitCommand only
            // fires for a focused responder, which this overlay may not have.
            Button("") { nav.paletteOpen = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onExitCommand { nav.paletteOpen = false }
        .task {
            // The hit→route join needs a catalog snapshot; refresh is coalesced.
            if !catalog.hasLoaded { await catalog.refresh() }
            focused = true
        }
        .onDisappear { model.cancel() }
    }

    private func open(_ hit: SearchHit) {
        guard let windowID = catalog.sessionWindowID(
            forSessionUuid: hit.sessionUuid, targetPromptUuid: hit.promptUuid
        ) else { return }
        // Dismiss FIRST — nav.go flips the window's route .id, and mutating
        // both in one synchronous pass tears this overlay down mid-update.
        nav.paletteOpen = false
        Task { @MainActor in nav.open(windowID) }
    }

    private func openSelectedOrFirst() {
        let target = model.hits.first { $0.rowID == selection } ?? model.hits.first
        if let target { open(target) }
    }

    private func moveSelection(_ delta: Int) {
        guard !model.hits.isEmpty else { return }
        let current = model.hits.firstIndex { $0.rowID == selection }
        let next = ((current ?? -1) + delta).clamped(to: 0...(model.hits.count - 1))
        selection = model.hits[next].rowID
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
