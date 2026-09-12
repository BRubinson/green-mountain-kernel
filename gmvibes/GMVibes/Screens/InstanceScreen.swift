import SwiftUI
import GMCCDaemonKit

/// The instance page: ALL of one instance's sessions, current-first. The
/// active (checked-out) session is resolved DAEMON-side
/// (INSTANCE_CURRENT_SESSION via CheckoutWatcher) and hoisted with the
/// outline + dot; a head-state strip explains branch / detached /
/// unavailable / unresolved. Nothing here auto-navigates — with no embedded
/// editor, "never auto-switch" is true by construction (the old
/// auto-load/drift machinery is gone; drift is simply the strip re-rendering
/// around a different active row).
struct InstanceScreen: View {
    let instanceUuid: String

    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(CatalogStore.self) private var catalog
    @Environment(CheckoutWatcher.self) private var checkout
    @Environment(WindowNav.self) private var nav

    @State private var showInactive = false
    @State private var filtered = FilteredCatalog()

    private var instance: InstanceRow? { catalog.instancesByUuid[instanceUuid] }

    /// The session row matching the checked-out branch, resolved daemon-side
    /// (INSTANCE_CURRENT_SESSION) — no client-side catalog scan.
    private var activeStub: SessionStub? {
        checkout.currentSession(instanceUuid: instanceUuid)
    }

    private var sessions: [SessionStub] {
        instance.map { filtered.sessions(of: $0) } ?? []
    }

    var body: some View {
        ScreenScaffold(title: instance?.name ?? "Instance") {
            VStack(spacing: 0) {
                identityStrip
                headStateStrip
                sessionList
            }
        }
        // House idiom: catalog stays fresh on topology invalidations.
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .topology)
            if !catalog.hasLoaded { await catalog.refresh() }
            checkout.ensureWatching(instanceUuid: instanceUuid, generation: daemon.generation)
            refilter()
            for await _ in stream {
                await catalog.refresh()
                checkout.ensureWatching(instanceUuid: instanceUuid, generation: daemon.generation)
                refilter()
            }
        }
        // The active hoist moves when the checked-out branch changes — the
        // strip and ordering follow; nothing navigates.
        .onChange(of: checkout.stateByInstance[instanceUuid]) { _, _ in refilter() }
        .onChange(of: catalog.sessionsByInstance) { _, _ in refilter() }
        .onChange(of: catalog.instancesByProject) { _, _ in refilter() }
        .sheet(isPresented: $showInactive) {
            // Project-level scope (per the brief): all of THIS project's
            // instances, not just this one.
            InactiveSessionsSheet(projectUuid: instance?.projectUuid)
        }
    }

    private func refilter() {
        var active: [String: String] = [:]
        if let stub = activeStub { active[instanceUuid] = stub.uuid }
        let next = CatalogFilter(
            query: SearchQuery(""),
            instanceUuid: instanceUuid,
            instanceOrder: .recency,
            sessionsPerInstance: nil,
            activeSessionByInstance: active,
            hoistActive: true
        ).apply(to: catalog)
        if filtered != next { filtered = next }
    }

    private var identityStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(instance?.name ?? "Instance")
                .font(.caption.weight(.semibold))
            if let path = instance?.absoluteFileSystemPath, !path.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                showInactive = true
            } label: {
                Label("Inactive Sessions", systemImage: "archivebox")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Browse non-active sessions across this project")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35))
    }

    /// Head-state surface: which session is checked out, or WHY none is —
    /// the four distinctions (branch without a session row / detached HEAD /
    /// unreadable path / unresolved) survive the inversion as a strip above
    /// the list rather than a full-page empty state.
    @ViewBuilder
    private var headStateStrip: some View {
        if let stub = activeStub {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Checked out: “\(stub.name)”")
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.green.opacity(0.08))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text(noActiveMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.10))
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No Sessions",
                systemImage: "arrow.triangle.branch",
                description: Text("This instance has no sessions in the GMCC database yet.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Backdrop())
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sessions, id: \.uuid) { stub in
                        sessionRow(stub)
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Backdrop())
        }
    }

    private func sessionRow(_ stub: SessionStub) -> some View {
        let active = stub.uuid == activeStub?.uuid
        return Button {
            openSession(stub)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stub.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(stub.code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(CatalogDates.relative(stub.lastActivityAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                // Hidden (not removed) so state changes never shift layout.
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .opacity(active ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .stateBorder(.green, active: active, cornerRadius: 12)
        .help(active ? "Checked out on this instance's repo" : stub.name)
    }

    private func openSession(_ stub: SessionStub) {
        // CatalogStore's factory: nil on a malformed uuid ⇒ inert row, never
        // a fabricated identity.
        guard let windowID = catalog.sessionWindowID(forSessionUuid: stub.uuid) else { return }
        nav.go(.session(windowID))
    }

    private var noActiveMessage: String {
        switch checkout.stateByInstance[instanceUuid] {
        case .some(let state) where state.headState == .branch:
            let display = state.currentBranch ?? state.currentSessionCode ?? "?"
            return "The checked-out branch “\(display)” has no matching session row on this instance."
        case .some(let state) where state.headState == .detached:
            return "This repo is on a detached HEAD — no branch is checked out."
        case .some:
            return "The instance's repo path is missing or unreadable."
        case .none:
            return "The checked-out branch hasn't been resolved yet (is the daemon running?)."
        }
    }
}
