import SwiftUI
import GMCCDaemonKit

/// Dedicated full-text search screen (`Route.search`). Same result list as
/// the ⌘K palette plus the affordances the overlay has no room for: a
/// session-scope toggle (SearchRequest.sessionUuid) and SearchKind filter
/// chips. Seeded with a session uuid when opened from a session's toolbar and
/// with a query when handed off from the palette's "Show all results".
struct SearchScreen: View {
    let seed: SearchSeed

    @Environment(CatalogStore.self) private var catalog
    @Environment(WindowNav.self) private var nav

    @State private var query = ""
    @State private var kinds: Set<SearchKind> = []   // empty = every kind
    @State private var scopeToSession = false
    @State private var selection: String?
    @State private var model = DaemonSearchModel(limit: 100)
    @FocusState private var focused: Bool

    private var scopedSession: SessionStub? {
        seed.sessionUuid.flatMap { catalog.session(uuid: $0) }
    }
    private var activeScopeUuid: String? {
        scopeToSession ? seed.sessionUuid : nil
    }

    var body: some View {
        VStack(spacing: 12) {
            CapsuleSearchField(
                prompt: "Search prompts, clarifications, architecture, exploration, review…",
                text: $query,
                focus: $focused
            )
            .onChange(of: query) { _, new in rerun(query: new) }

            HStack(spacing: 8) {
                if let session = scopedSession {
                    Toggle(isOn: $scopeToSession) {
                        Text("Only \(session.name)").font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: scopeToSession) { _, _ in rerun(debounce: .zero) }
                    Divider().frame(height: 14)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SearchKind.allCases, id: \.self) { kind in
                            SearchKindChip(kind: kind, isOn: kinds.contains(kind)) {
                                if kinds.contains(kind) {
                                    kinds.remove(kind)
                                } else {
                                    kinds.insert(kind)
                                }
                                rerun(debounce: .zero)
                            }
                        }
                    }
                    .padding(2)   // room for the chips' state borders
                }
                if !kinds.isEmpty {
                    Button("Clear") {
                        kinds = []
                        rerun(debounce: .zero)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            SearchResultsList(
                hits: model.hits,
                searched: model.searched,
                errorText: model.errorText,
                selection: $selection,
                idleDescription: scopeToSession
                    ? "Full-text search within this session."
                    : "Full-text search across every session in the GMCC database.",
                destination: { catalog.sessionWindowID(forSessionUuid: $0.sessionUuid) },
                onOpen: open
            )
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .navigationTitle("Search")
        .navigationSubtitle(scopeToSession ? (scopedSession?.name ?? "Session") : "All sessions")
        .task {
            if !catalog.hasLoaded { await catalog.refresh() }   // the join needs a snapshot
            scopeToSession = seed.sessionUuid != nil
            focused = true
            // Mutating query fires the field's own onChange, which schedules
            // the (debounced) search — no second dispatch needed.
            if !seed.query.isEmpty { query = seed.query }
        }
        .onDisappear { model.cancel() }
    }

    private func rerun(query newQuery: String? = nil, debounce: Duration = .milliseconds(300)) {
        selection = nil
        model.schedule(
            query: newQuery ?? query,
            sessionUuid: activeScopeUuid,
            kinds: kinds,
            debounce: debounce
        )
    }

    private func open(_ hit: SearchHit) {
        guard let windowID = catalog.sessionWindowID(
            forSessionUuid: hit.sessionUuid, targetPromptUuid: hit.promptUuid
        ) else { return }
        nav.open(windowID)   // route swap, no presenter to tear down
    }
}
