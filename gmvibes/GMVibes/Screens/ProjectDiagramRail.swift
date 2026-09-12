import SwiftUI
import GMCCDaemonKit

/// The project page's right-hand diagram gallery.
///
/// The browse surface is DIAGRAM_SEARCH across ALL tiers — the project page
/// is where every diagram in the project is findable, which is exactly the
/// union DIAGRAM_LIST refuses to be. The create path still runs on the
/// PROJECT-tier owner list (uniqueCode needs exactly that tier's codes).
///
/// Above the cards sits the COMPUTED persistence diagram: the project's
/// own dope scope (the PROJECT_ITEM overlay, else the BASE_PROJECT scope
/// `gm dope promote` maintains) laid out on the fly. It is a preview — no
/// diagram row, nothing written — so opening the project's domain model never
/// mints a document nobody asked for.
struct ProjectDiagramRail: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramCatalogStore.self) private var diagrams
    @Environment(CatalogStore.self) private var catalog
    let projectUuid: String
    let onOpen: (DiagramWindowID) -> Void

    /// The project's dope scope code, read once. There is no project-tier
    /// dope STORE (DopeStore is per session scope) and nothing else on this
    /// page wants the tree — so this is one read for the create path's
    /// binding and the computed row's label, not a cache.
    @State private var dopeScopeCode: String?
    @State private var busy = false
    @State private var actionError: String?

    private var owner: DiagramCatalogStore.Owner { .project(projectUuid) }
    private var rows: [DiagramRow] { diagrams.rows(owner) }
    private var galleryScope: DiagramCatalogStore.GalleryScope { .project(projectUuid) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            computedRow
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            if let error = diagrams.errorsByOwner[owner] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            Divider()
            DiagramGalleryView(scope: galleryScope, onOpen: { row in
                // The rail has no session window to hand a SESSION/PROMPT
                // row — nil is the legal "caller doesn't know" state.
                onOpen(DiagramWindowID.saved(row, session: nil))
            }) { row in
                cardMenu(row)
            }
        }
        // Wide enough for two thumbnail columns — a gallery, not a list.
        .frame(width: 440)
        .background(.background.secondary)
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .diagramList(projectUuid))
            await diagrams.refresh(owner)
            await loadDopeCode()
            for await _ in stream {
                await diagrams.refresh(owner)
            }
        }
        .alert("Diagram action failed", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Diagrams").font(.headline)
            Spacer(minLength: 0)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(action: create) {
                    Label("New Project Diagram", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Create a project diagram over the project's dope scope")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The always-present computed row. Deliberately not a saved diagram and
    /// deliberately not hidden when saved ones exist: it is the live view of
    /// the project's domain model, and it is always current because nothing
    /// persists it.
    private var computedRow: some View {
        Button {
            onOpen(DiagramWindowID(source: .dopePreview(scopeCode: dopeScopeCode),
                                   name: "Project Persistence",
                                   session: nil, projectUuid: projectUuid))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Project Persistence").font(.body)
                    Text(dopeScopeCode.map { "\($0) · computed" } ?? "computed from dope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("The project's dope scope, laid out live — a preview, never saved")
    }

    @ViewBuilder
    private func cardMenu(_ row: DiagramRow) -> some View {
        if row.tier == DiagramTier.project.rawValue {
            let sessions = projectSessions
            if sessions.isEmpty {
                Text("No sessions to move this into")
            } else {
                Menu("Move to Session") {
                    ForEach(sessions, id: \.uuid) { session in
                        Button(session.name) { move(row, to: session.uuid) }
                    }
                }
            }
            Divider()
        }
        Button("Delete Diagram", role: .destructive) { delete(row) }
    }

    /// The project's sessions, most recent first — the promote-DOWN targets.
    /// Capped: a mature project has hundreds, and a menu is not a browser.
    private var projectSessions: [SessionStub] {
        (catalog.instancesByProject[projectUuid] ?? [])
            .flatMap { catalog.sessionsByInstance[$0.uuid] ?? [] }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
            .prefix(12)
            .map { $0 }
    }

    // MARK: - Actions

    private func loadDopeCode() async {
        // A project with no dope scope yet is normal — the row then just says
        // "computed from dope" and the create path binds nothing.
        guard let response = try? await GMCCDaemonService.shared.dopeGet(
            projectUuid: projectUuid) else { return }
        dopeScopeCode = response.tree.body.code
    }

    private func create() {
        run {
            let base = dopeScopeCode.map { "\($0)_canvas" } ?? "project_canvas"
            let code = SessionDiagramsPane.uniqueCode(base: base,
                                                      taken: Set(rows.map(\.code)))
            _ = try await diagrams.create(
                owner: owner, code: code,
                name: dopeScopeCode.map { "\($0) canvas" } ?? "Project Diagram",
                dopeScopeCode: dopeScopeCode, projectUuid: projectUuid)
        }
    }

    private func move(_ row: DiagramRow, to sessionUuid: String) {
        run {
            try await diagrams.promote(row, to: .session, ownerUuid: sessionUuid,
                                       from: owner)
            await diagrams.refreshGallery(galleryScope)
        }
    }

    private func delete(_ row: DiagramRow) {
        run {
            try await diagrams.delete(row, scope: galleryScope)
            await diagrams.refresh(owner)
        }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await body()
            } catch let error as LocalizedError {
                actionError = error.errorDescription ?? String(describing: error)
            } catch let error as DaemonError {
                actionError = error.userMessage
            } catch {
                actionError = String(describing: error)
            }
            busy = false
        }
    }
}
