import SwiftUI
import GMCCDaemonKit

/// The PROJECT page (`Route.project`): all of one project's instances,
/// searchable, with the last 5 sessions of each rendered inline — the active
/// session hoisted first with the recents outline + dot. Clicks drill down:
/// instance row → `Route.instance`, session block → `Route.session`.
struct ProjectScreen: View {
    let projectUuid: String

    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(CatalogStore.self) private var catalog
    @Environment(CheckoutWatcher.self) private var checkout
    @Environment(WindowNav.self) private var nav

    @State private var query = ""
    @State private var filtered = FilteredCatalog()
    @State private var activeByInstance: [String: String] = [:]

    private var project: ProjectRow? {
        catalog.projects.first { $0.uuid == projectUuid }
    }

    var body: some View {
        ScreenScaffold(
            title: project?.name ?? "Project",
            subtitle: (project?.gitRepoName.isEmpty == false) ? project?.gitRepoName : nil
        ) {
            // The rail is a sibling of the content, not an overlay: it holds
            // the project's diagrams, which are as much this page's subject
            // as its instances are.
            HStack(spacing: 0) {
                content
                    .searchable(text: $query, placement: .toolbar,
                                prompt: "Search instances & sessions")
                Divider()
                ProjectDiagramRail(projectUuid: projectUuid) { diagramID in
                    nav.go(.diagram(diagramID))
                }
            }
        }
        // House idiom: catalog stays fresh on topology invalidations; the
        // filter re-derives after every refresh (derived @State, never a
        // computed walk per body pass).
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .topology)
            if !catalog.hasLoaded { await catalog.refresh() }
            ensureWatchingAndRefilter()
            for await _ in stream {
                await catalog.refresh()
                ensureWatchingAndRefilter()
            }
        }
        .onChange(of: query) { _, _ in refilter() }
        .onChange(of: catalog.projects) { _, _ in refilter() }
        .onChange(of: catalog.instancesByProject) { _, _ in refilter() }
        .onChange(of: catalog.sessionsByInstance) { _, _ in refilter() }
        .onChange(of: checkout.stateByInstance) { _, _ in refilter() }
    }

    @ViewBuilder
    private var content: some View {
        let instances = project.map { filtered.instances(of: $0) } ?? []
        if instances.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No Instances" : "No Matches",
                systemImage: query.isEmpty ? "internaldrive" : "magnifyingglass",
                description: Text(query.isEmpty
                    ? "This project has no instances in the GMCC database."
                    : "Nothing matches “\(query)”.")
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(instances, id: \.uuid) { instance in
                        InstanceSessionBlock(
                            instance: instance,
                            sessions: filtered.sessions(of: instance),
                            totalSessions: filtered.totalSessions[instance.uuid] ?? 0,
                            activeSessionUuid: activeByInstance[instance.uuid],
                            onOpenInstance: { nav.go(.instance(instanceUuid: instance.uuid)) },
                            onOpenSession: { openSession($0, instance) }
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Backdrop())
        }
    }

    private func ensureWatchingAndRefilter() {
        for instance in catalog.instancesByProject[projectUuid] ?? [] {
            checkout.ensureWatching(instanceUuid: instance.uuid, generation: daemon.generation)
        }
        refilter()
    }

    private func refilter() {
        var active: [String: String] = [:]
        for instance in catalog.instancesByProject[projectUuid] ?? [] {
            if let stub = checkout.currentSession(instanceUuid: instance.uuid) {
                active[instance.uuid] = stub.uuid
            }
        }
        let next = CatalogFilter(
            query: SearchQuery(query),
            projectUuid: projectUuid,
            instanceOrder: .alphabetical,
            sessionsPerInstance: 5,
            activeSessionByInstance: active,
            hoistActive: true
        ).apply(to: catalog)
        if activeByInstance != active { activeByInstance = active }
        if filtered != next { filtered = next }
    }

    private func openSession(_ stub: SessionStub, _ instance: InstanceRow) {
        // CatalogStore's factory: nil on a malformed uuid ⇒ inert row, never
        // a fabricated identity.
        guard let windowID = catalog.sessionWindowID(forSessionUuid: stub.uuid) else { return }
        nav.go(.session(windowID))
    }
}
