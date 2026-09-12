import SwiftUI
import GMCCDaemonKit

// MARK: - Root view
//
// File-explorer tree over the daemon's entity hierarchy: projects are folders,
// instances are folders nested inside them, sessions are leaf rows. The whole
// tree comes from CatalogStore's three Listing calls, refreshed on topology
// events (no polling); clicking a session opens the per-session editor window.
// Selection/expansion is purely local tree state.

struct ProjectsView: View {
    @State private var query: String = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        // ScreenScaffold hosts only the title + searchable chrome (no path).
        ScreenScaffold(title: "Projects") {
            ProjectTreeView(query: $query, expanded: $expanded)
                .searchable(text: $query, placement: .toolbar,
                            prompt: "Search projects, instances & sessions")
        }
    }
}

// MARK: - Project tree (the whole screen)

private struct ProjectTreeView: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(CatalogStore.self) private var catalog

    @Binding var query: String
    @Binding var expanded: Set<String>
    // Derived in @State (house rule): typing a character rescans the tree
    // once, not once per body pass. The traversal itself is CatalogFilter —
    // the app's ONE tree walk.
    @State private var filtered = FilteredCatalog()

    var body: some View {
        List {
            ForEach(filtered.projects, id: \.uuid) { project in
                ProjectFolderRow(project: project,
                                 filtered: filtered,
                                 searching: !query.isEmpty,
                                 expanded: $expanded)
            }
            if filtered.projects.isEmpty {
                emptyRow
            }
        }
        .listStyle(.sidebar)
        // Event-driven refresh; generation restarts the loop after reconnect.
        // Stream hoisted before the first refresh so an invalidation firing
        // during the initial fetch isn't lost.
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .topology)
            await catalog.refresh()
            refilter()
            for await _ in stream {
                await catalog.refresh()
                refilter()
            }
        }
        .onChange(of: query) { _, _ in refilter() }
        // The derived-@State conversion loses the free re-derivation the old
        // computed properties got from body reads — EVERY published catalog
        // axis this snapshot folds must be observed, or a rename sticks
        // until an unrelated event.
        .onChange(of: catalog.projects) { _, _ in refilter() }
        .onChange(of: catalog.instancesByProject) { _, _ in refilter() }
        .onChange(of: catalog.sessionsByInstance) { _, _ in refilter() }
    }

    private func refilter() {
        // This browser keeps the catalog's recency order (the drill-down
        // pages are the alphabetical surfaces) and SHOWS instance-less
        // projects (the tree renders a "No instances." row for them).
        let next = CatalogFilter(query: SearchQuery(query), instanceOrder: .recency,
                                 includeEmptyProjects: true)
            .apply(to: catalog)
        if filtered != next { filtered = next }
    }

    private var emptyRow: some View {
        Text(emptyText)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowSeparator(.hidden)
    }

    private var emptyText: String {
        if !query.isEmpty { return "No matches." }
        if daemon.health != .up { return "GMCC daemon unavailable." }
        if let error = catalog.lastError { return error }
        return "No projects in the GMCC database yet — start a session in a gmcc-enabled repo (gmcc_hook context ensure)."
    }
}

// MARK: - Project folder (level 0)

private struct ProjectFolderRow: View {
    let project: ProjectRow
    let filtered: FilteredCatalog
    let searching: Bool
    @Binding var expanded: Set<String>

    @State private var showingSettings = false

    var body: some View {
        DisclosureGroup(isExpanded: expansionBinding) {
            InstanceLevel(project: project,
                          filtered: filtered,
                          searching: searching,
                          expanded: $expanded)
        } label: {
            HStack(spacing: 6) {
                FolderLabel(name: project.name, subtitle: project.code,
                            systemImage: "folder")
                Spacer(minLength: 4)
                // Always rendered, matching the landing card. Hover-reveal
                // was tried first and simply could not be found.
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project settings")
                .accessibilityLabel("Project settings for \(project.name)")
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Project Settings…") { showingSettings = true }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ProjectSettingsSheet(projectUuid: project.uuid)
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expanded.contains(project.uuid) || filtered.expandedAncestors.contains(project.uuid) },
            set: { open in
                if open { expanded.insert(project.uuid) } else { expanded.remove(project.uuid) }
            }
        )
    }
}

// Instances of a project — read straight from the filtered snapshot.
private struct InstanceLevel: View {
    let project: ProjectRow
    let filtered: FilteredCatalog
    let searching: Bool
    @Binding var expanded: Set<String>

    var body: some View {
        let instances = filtered.instances(of: project)
        if instances.isEmpty {
            Text(searching ? "No matching instances." : "No instances.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(instances, id: \.uuid) { instance in
                InstanceFolderRow(instance: instance,
                                  filtered: filtered,
                                  searching: searching,
                                  expanded: $expanded)
            }
        }
    }
}

// MARK: - Instance folder (level 1)

private struct InstanceFolderRow: View {
    let instance: InstanceRow
    let filtered: FilteredCatalog
    let searching: Bool
    @Binding var expanded: Set<String>

    var body: some View {
        DisclosureGroup(isExpanded: expansionBinding) {
            SessionLevel(instance: instance,
                         filtered: filtered,
                         searching: searching)
        } label: {
            FolderLabel(name: instance.name, subtitle: instance.code,
                        systemImage: "folder")
        }
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expanded.contains(instance.uuid) || filtered.expandedAncestors.contains(instance.uuid) },
            set: { open in
                if open { expanded.insert(instance.uuid) } else { expanded.remove(instance.uuid) }
            }
        )
    }
}

// Sessions of an instance — read straight from the filtered snapshot.
private struct SessionLevel: View {
    let instance: InstanceRow
    let filtered: FilteredCatalog
    let searching: Bool

    var body: some View {
        let sessions = filtered.sessions(of: instance)
        if sessions.isEmpty {
            Text(searching ? "No matching sessions." : "No sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(sessions, id: \.uuid) { session in
                SessionLeafRow(session: session, instance: instance)
            }
        }
    }
}

// MARK: - Session leaf (level 2)

private struct SessionLeafRow: View {
    @Environment(WindowNav.self) private var nav
    @Environment(CatalogStore.self) private var catalog
    let session: SessionStub
    let instance: InstanceRow

    var body: some View {
        Button {
            // Navigate this window to the session. The factory returns nil on
            // a malformed uuid — the row goes inert rather than fabricating
            // an identity for a dead screen (CatalogStore's contract).
            guard let windowID = catalog.sessionWindowID(forSessionUuid: session.uuid) else { return }
            nav.go(.session(windowID))
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.body)
                    HStack(spacing: 6) {
                        // The code IS the session's identity (slugged branch,
                        // forward-only) — rendered verbatim; the raw branch is
                        // a wire fact only for the checked-out session.
                        Text(session.code)
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared folder label

private struct FolderLabel: View {
    let name: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}
