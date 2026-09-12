import SwiftUI
import GMCCDaemonKit

/// Browser for NON-checked-out sessions. PROJECT-level: scoped to one project
/// when the caller passes its uuid (the instance page does), searching across
/// all that project's instances — never limited to a single instance. The
/// landing page passes nil for the all-projects view. Clicking a row loads
/// the session view — the same screen as an active session, just not the
/// checked-out branch.
struct InactiveSessionsSheet: View {
    /// Scope to one project; nil = all projects.
    var projectUuid: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog
    @Environment(CheckoutWatcher.self) private var checkout
    @Environment(WindowNav.self) private var nav

    @State private var query = ""
    // Derived in @State (not a computed property) so typing a character
    // doesn't rescan the whole catalog on every body pass.
    @State private var rows: [Row] = []

    private struct Row: Identifiable, Equatable {
        let windowID: SessionWindowID
        let sessionName: String
        let branch: String?
        let projectName: String
        let instanceName: String
        var id: UUID { windowID.sessionUUID }
    }

    private func deriveRows() {
        // The tree walk is CatalogFilter (the app's one traversal); this just
        // flattens its snapshot into presentable rows.
        var checkedOut: [String: String] = [:]
        for uuid in catalog.instancesByUuid.keys {
            if let code = checkout.checkedOutCode(instanceUuid: uuid) {
                checkedOut[uuid] = code
            }
        }
        let filtered = CatalogFilter(
            query: SearchQuery(query),
            projectUuid: projectUuid,
            instanceOrder: .recency,
            checkedOutCodeByInstance: checkedOut,
            excludeCheckedOut: true
        ).apply(to: catalog)

        var out: [Row] = []
        for project in filtered.projects {
            for instance in filtered.instances(of: project) {
                guard let instanceUUID = UUID(uuidString: instance.uuid) else { continue }
                for stub in filtered.sessions(of: instance) {
                    guard let sessionUUID = UUID(uuidString: stub.uuid) else { continue }
                    out.append(Row(
                        windowID: SessionWindowID(
                            sessionUUID: sessionUUID,
                            instanceUUID: instanceUUID,
                            sessionName: stub.name
                        ),
                        sessionName: stub.name,
                        branch: stub.code,
                        projectName: project.name,
                        instanceName: instance.name
                    ))
                }
            }
        }
        if rows != out { rows = out }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Inactive Sessions")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            CapsuleSearchField(prompt: "Search sessions across all instances", text: $query)

            let listed = rows
            if listed.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No inactive sessions" : "No matches",
                    systemImage: query.isEmpty ? "archivebox" : "magnifyingglass",
                    description: Text(query.isEmpty
                        ? "Every session is currently checked out on its instance."
                        : "No inactive session matches “\(query)”.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(listed) { row in
                            Button {
                                // Dismiss FIRST: nav.go flips the window's
                                // route .id and would tear down this sheet's
                                // presenter mid-update. Navigate next turn.
                                dismiss()
                                let target = row.windowID
                                Task { @MainActor in nav.go(.session(target)) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.sessionName)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(row.projectName) · \(row.instanceName)\(row.branch.map { " · \($0)" } ?? "")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { deriveRows() }
        .onChange(of: query) { _, _ in deriveRows() }
        .onChange(of: catalog.sessionsByInstance) { _, _ in deriveRows() }
        .onChange(of: checkout.stateByInstance) { _, _ in deriveRows() }
    }
}
