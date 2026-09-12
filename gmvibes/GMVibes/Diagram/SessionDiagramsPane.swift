import SwiftUI
import GMCCDaemonKit

/// The session view's DIAGRAMS tab — a real list of the session's SAVED
/// diagrams (DIAGRAM_LIST at SESSION tier), not the dope scopes it used to
/// show. A diagram is a document now; the scope it is drawn over is one of
/// its properties, not its identity.
///
/// Creating one binds it to a dope scope (read through the session's existing
/// DopeStore, so the tab shares one cache with the dope tab) and the CREATE
/// is what seeds the canvas — see DiagramCatalogStore.create. Importing pulls
/// a PROJECT-tier diagram down into this session as a copy.
struct SessionDiagramsPane: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramCatalogStore.self) private var diagrams
    let scope: SessionScope
    let windowID: SessionWindowID
    let projectUuid: String
    let onOpen: (DiagramWindowID) -> Void

    @State private var busy = false
    @State private var actionError: String?

    private var dopeStore: DopeStore { scope.dope }
    private var scopes: [DopeScopeRow] { dopeStore.sessionCandidates(.init(promptUuid: nil)) }
    private var owner: DiagramCatalogStore.Owner { .session(scope.sessionUuid) }
    private var rows: [DiagramRow] { diagrams.rows(owner) }
    private var projectRows: [DiagramRow] { diagrams.rows(.project(projectUuid)) }
    private var galleryScope: DiagramCatalogStore.GalleryScope {
        .session(projectUuid: projectUuid, sessionUuid: scope.sessionUuid)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: daemon.generation) {
            let stream = daemon.hub.stream(for: .diagramList(scope.sessionUuid))
            await dopeStore.refresh(promptUuid: nil)
            await diagrams.refresh(owner)
            await diagrams.refresh(.project(projectUuid))
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

    // MARK: - Header actions

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                if scopes.isEmpty {
                    Text("Initialize a dope scope from the Dope tab first")
                } else {
                    ForEach(scopes, id: \.uuid) { row in
                        Button("\(row.name)  ·  \(row.code)") { create(from: row) }
                    }
                }
            } label: {
                Label("New Diagram", systemImage: "plus")
            }
            .disabled(busy)
            .help("Create a session diagram over one dope scope — the canvas is "
                  + "scaffolded from that scope once, at creation")

            Menu {
                if projectRows.isEmpty {
                    Text("This project has no project-tier diagrams")
                } else {
                    ForEach(projectRows, id: \.uuid) { row in
                        Button("\(row.name)  ·  \(row.code)") { importProjectDiagram(row) }
                    }
                }
            } label: {
                Label("Import Project Diagram", systemImage: "square.and.arrow.down")
            }
            .disabled(busy || projectRows.isEmpty)
            .help("Copy a project diagram into this session")

            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The session gallery: this session's SESSION+PROMPT rows via
    /// DIAGRAM_SEARCH — a wider net than the session-owner list the header
    /// actions still run on (uniqueCode needs exactly the owner's codes).
    private var content: some View {
        DiagramGalleryView(scope: galleryScope, onOpen: { row in
            onOpen(DiagramWindowID.saved(row, session: windowID))
        }) { row in
            cardMenu(row)
        }
    }

    @ViewBuilder
    private func cardMenu(_ row: DiagramRow) -> some View {
        if row.tier == DiagramTier.session.rawValue {
            Button("Promote to Project") { promote(row) }
                .help("Move this diagram up to the project tier")
        }
        // PUBLIC is SESSION-tier only, but the daemon owns that rule — a
        // refusal surfaces through the existing error alert, not a pre-block.
        if row.visibility == DiagramVisibility.public.rawValue {
            Button("Make Private") { setVisibility(row, .private) }
        } else {
            Button("Make Public") { setVisibility(row, .public) }
                .help("PUBLIC session diagrams can serialize into the repo's "
                      + "committed .gmcc tree via DIAGRAM_WRITE_REPO")
        }
        Divider()
        Button("Delete Diagram", role: .destructive) { delete(row) }
    }

    // MARK: - Actions

    private func create(from scopeRow: DopeScopeRow) {
        run {
            let code = Self.uniqueCode(base: "\(scopeRow.code)_canvas",
                                       taken: Set(rows.map(\.code)))
            _ = try await diagrams.create(
                owner: owner, code: code, name: scopeRow.name,
                dopeScopeCode: scopeRow.code, projectUuid: projectUuid,
                sessionUuid: scope.sessionUuid)
        }
    }

    private func importProjectDiagram(_ row: DiagramRow) {
        run {
            let code = Self.uniqueCode(base: row.code, taken: Set(rows.map(\.code)))
            _ = try await diagrams.copy(row, to: owner, code: code, name: row.name,
                                        projectUuid: projectUuid)
        }
    }

    private func promote(_ row: DiagramRow) {
        run {
            try await diagrams.promote(row, to: .project, ownerUuid: projectUuid,
                                       from: owner)
            await diagrams.refreshGallery(galleryScope)
        }
    }

    private func setVisibility(_ row: DiagramRow, _ visibility: DiagramVisibility) {
        run {
            try await diagrams.setVisibility(row, to: visibility, scope: galleryScope)
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

    /// DIAGRAM_INIT is idempotent per (owner, code) — reusing a code would
    /// silently hand back the EXISTING diagram instead of making a new one,
    /// so a copy or a second canvas over one scope needs a fresh code.
    static func uniqueCode(base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base)_\(index)") { index += 1 }
        return "\(base)_\(index)"
    }
}

