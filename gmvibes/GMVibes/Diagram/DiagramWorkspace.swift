import SwiftUI
import Observation
import GMCCDaemonKit

/// Window-lifetime diagram state, keyed by `DiagramWindowID.workspaceKey` —
/// the DIAGRAM's identity (its uuid when saved, owner+scope for a preview),
/// not the session's. Held as `@State` on `GMVibesWindow` above the
/// `.id(nav.route)` boundary and injected with `.environment` — the exact
/// seam `DrawingsStore` occupied — so viewport, selection and any
/// non-persisted canvas survive in-window navigation and die with the
/// window. Deliberately NOT SessionScopeCache (its grace list would
/// resurrect a closed window's workspace).
@Observable @MainActor
final class DiagramWorkspaceStore {
    /// @ObservationIgnored makes create-or-get legal from a view body (the
    /// DrawingsStore rule): a TRACKED dictionary would register a read
    /// dependency and then write inside the same tracking scope. Each
    /// DiagramWorkspace is the real observable unit.
    @ObservationIgnored private var workspaces: [String: DiagramWorkspace] = [:]

    /// Create-or-get, side-effect-safe from a view body.
    func workspace(for id: DiagramWindowID) -> DiagramWorkspace {
        if let existing = workspaces[id.workspaceKey] { return existing }
        let fresh = DiagramWorkspace(id: id)
        workspaces[id.workspaceKey] = fresh
        return fresh
    }
}

/// The MODEL half of the diagram screen (the view-state half is
/// `DiagramViewState`). The split is the freeze-during-drag guarantee made
/// structural: `resolved` is a STORED property whose only writers are
/// `adopt` / `reproject` / `reskin` — a drag sample writes only view state,
/// so per-property observation makes a per-sample re-resolve (and the A*
/// pass inside it) impossible rather than merely forbidden.
///
/// TWO sources, one behavior (`DiagramWindowID.Source`):
///  - `.saved` — a db diagram. DIAGRAM_GET loads it, every write is a
///    DIAGRAM_BATCH_APPLY through `DaemonDiagramCommitter`, and the dope
///    scaffold is NOT re-run on load: the tree is the document, seeded once
///    at create time by `DiagramCatalogStore`.
///  - `.dopePreview` — the computed, non-persisted canvas over one dope
///    scope. Scaffolded in memory through `DopeCanvasLayout` and committed
///    to `LocalDiagramCommitter`; nothing reaches the db.
@Observable @MainActor
final class DiagramWorkspace {
    let id: DiagramWindowID

    private(set) var tree: DiagramTree
    /// What the screen draws: the resolve with unselected domains hidden.
    private(set) var resolved: ResolvedDiagram
    /// Bumped once per adopted tree or filter change — the cheap "content
    /// changed" signal.
    private(set) var generation = 0
    private(set) var loaded = false
    private(set) var loadError: String?

    /// The single write funnel (kit type, verbatim): stage/restage during a
    /// gesture, one flush at gesture end.
    private(set) var editSession: DiagramEditSession!

    /// The dope tree the cards are drawn from (search and the domain pills
    /// run over this). The FIRST bound scope when a canvas binds several.
    private(set) var dope: DopeGetResponse?
    /// Multi-pill domain filter: empty = all domains shown. A RENDER-TIME
    /// filter (see DiagramDomainFilter) — never a tree rebuild.
    private(set) var domainFilter: Set<String> = []

    /// The filter-blind resolve. Stored so a pill toggle re-projects instead
    /// of re-resolving (which would re-run the A* edge routing).
    @ObservationIgnored private var fullResolved: ResolvedDiagram
    /// scope code -> the hydrated dope tree that code resolved to.
    @ObservationIgnored private var dopeEntries: [String: DiagramDopeContext.Entry] = [:]
    /// Preview mode only: the in-memory authority the local committer writes.
    @ObservationIgnored private var box: DiagramTreeBox?
    /// Preview mode only: entity code -> last authored center, carried across
    /// dope reloads (a preview re-scaffolds; a saved diagram never does).
    @ObservationIgnored private var codeCenters: [String: CGPoint] = [:]

    private var colorScheme: DiagramRenderEnvironment.ColorScheme = .light
    private let service = GMCCDaemonService.shared

    init(id: DiagramWindowID) {
        self.id = id
        let empty = Self.emptyTree(id: id)
        self.tree = empty
        let resolved = DiagramResolver.resolve(empty, dope: DiagramDopeContext())
        self.fullResolved = resolved
        self.resolved = resolved
        switch id.source {
        case .saved(let diagramUuid):
            self.editSession = DiagramEditSession(
                committer: DaemonDiagramCommitter(diagramUuid: diagramUuid) { [weak self] response in
                    self?.adopt(response.tree)
                },
                baseRevision: nil)
        case .dopePreview:
            let box = DiagramTreeBox(tree: empty)
            self.box = box
            self.editSession = DiagramEditSession(
                committer: LocalDiagramCommitter(box: box) { [weak self] newTree in
                    // The box ALREADY holds newTree (it applied the batch),
                    // so no replace — a detached replace here raced the
                    // rebase and produced spurious revision conflicts.
                    self?.adopt(newTree)
                },
                baseRevision: 0)
        }
    }

    private static func emptyTree(id: DiagramWindowID) -> DiagramTree {
        let now = ISO8601DateFormatter().string(from: Date())
        let session = id.session?.sessionUUID.wireString
        return DiagramTree(
            identity: DopeNodeIdentity(uuid: id.savedDiagramUuid ?? UUID().uuidString.lowercased(),
                                       version: 0, createdAt: now, updatedAt: now),
            tier: session == nil ? "PROJECT" : "SESSION",
            projectUuid: id.projectUuid, instanceUuid: nil,
            sessionUuid: session, promptUuid: nil,
            code: id.previewScopeCode ?? id.name, name: id.name, description: "",
            gmccDiagramPath: nil, revision: 0, elements: [])
    }

    private var environment: DiagramRenderEnvironment {
        DiagramRenderEnvironment(colorScheme: colorScheme)
    }

    private var dopeContext: DiagramDopeContext {
        DiagramDopeContext(entries: dopeEntries)
    }

    // MARK: - Loading

    /// First load. Idempotent: a second call re-reads rather than
    /// re-scaffolding, so a generation bump or a re-entered screen never
    /// resets a canvas the user has moved.
    func load(scheme: ColorScheme) async {
        colorScheme = scheme == .dark ? .dark : .light
        switch id.source {
        case .saved:
            await reloadDiagram()
        case .dopePreview(let code):
            await loadPreview(scopeCode: code)
        }
    }

    /// DIAGRAM_CHANGE wake (or a post-flush conflict recovery): re-read the
    /// row, then the dope trees its bindings name.
    func reloadDiagram() async {
        guard let diagramUuid = id.savedDiagramUuid else { return }
        do {
            let response = try await service.diagramGet(diagramUuid: diagramUuid)
            await loadDopeEntries(for: response)
            adopt(response.tree)
            loadError = nil
            loaded = true
        } catch let error as DaemonError {
            loadError = error.userMessage
        } catch {
            loadError = String(describing: error)
        }
    }

    /// DOPE_CHANGE wake. A SAVED diagram only RE-RESOLVES: its cards are
    /// rows, so a new dope entity does not silently mint one — the scaffold
    /// is a create-time act. A preview re-scaffolds, since its whole content
    /// is derived and nothing is persisted to lose.
    func reloadDope() async {
        switch id.source {
        case .saved:
            // Same read either way — the dope trees hang off the diagram's
            // own bindings, so re-reading the row is how they refresh.
            await reloadDiagram()
        case .dopePreview(let code):
            await loadPreview(scopeCode: code, rescaffold: true)
        }
    }

    /// Fetch one dope tree per bound scope code. Bindings resolve through the
    /// diagram's OWN owner chain — a session/prompt read for session-owned
    /// diagrams, the project ladder (PROJECT_ITEM, else BASE_PROJECT) for a
    /// project-tier one, which has no session to read through at all.
    private func loadDopeEntries(for response: DiagramGetResponse) async {
        var entries: [String: DiagramDopeContext.Entry] = [:]
        var primary: DopeGetResponse?
        for code in Self.boundScopeCodes(in: response.tree.elements) {
            guard let dope = try? await fetchDope(
                sessionUuid: response.tree.sessionUuid,
                promptUuid: response.tree.promptUuid,
                // The TREE's project, not the route payload's: the row is
                // authoritative about its own owner chain, and a promotion
                // can have moved it since the route was built.
                projectUuid: response.tree.projectUuid, code: code) else {
                // A code matching nothing is the LEGAL ghost state, not an
                // error: the resolver renders an absent scope card.
                continue
            }
            entries[code] = DiagramDopeContext.Entry(
                tree: dope.tree, resolvedVia: dope.resolvedVia)
            if primary == nil { primary = dope }
        }
        dopeEntries = entries
        dope = primary
    }

    private func fetchDope(sessionUuid: String?, promptUuid: String?,
                           projectUuid: String? = nil,
                           code: String?) async throws -> DopeGetResponse {
        if let sessionUuid {
            return try await service.dopeGet(sessionUuid: sessionUuid,
                                             promptUuid: promptUuid, code: code)
        }
        return try await service.dopeGet(projectUuid: projectUuid ?? id.projectUuid,
                                         code: code)
    }

    private static func boundScopeCodes(in elements: [DiagramElementNode]) -> [String] {
        var codes: [String] = []
        for element in elements {
            if case .dopeScopePersistenceLayer(let payload) = element.payload,
               !codes.contains(payload.dopeScopeCode) {
                codes.append(payload.dopeScopeCode)
            }
        }
        return codes
    }

    // MARK: - Preview scaffold

    /// The non-persisted path: read the dope scope, lay it out once through
    /// `DopeCanvasLayout` (the CLI generator's own layout — heights come from
    /// the resolver, so the app and the daemon can never lay out
    /// differently), apply it with the parity-tested reducer.
    private func loadPreview(scopeCode: String?, rescaffold: Bool = false) async {
        do {
            let response = try await fetchDope(
                sessionUuid: id.session?.sessionUUID.wireString,
                promptUuid: nil, code: scopeCode)
            dopeEntries = [response.tree.body.code: DiagramDopeContext.Entry(
                tree: response.tree, resolvedVia: response.resolvedVia)]
            dope = response
            loadError = nil
            if !loaded || rescaffold {
                scaffoldPreview(from: response.tree)
            }
            loaded = true
        } catch let error as DaemonError {
            loadError = error.userMessage
        } catch {
            loadError = String(describing: error)
        }
    }

    private func scaffoldPreview(from dopeTree: DopeScopeTree) {
        guard let box else { return }
        // A re-scaffold re-mints every element uuid — anything staged against
        // the old tree (a drag in flight when a dope event lands) is poison
        // and must be dropped BEFORE the swap.
        editSession.discard()
        rememberCenters()
        var mutations = DopeCanvasLayout.mutations(for: dopeTree)
        // Carryover: a card whose entity code was placed before keeps its
        // center across reloads.
        mutations = mutations.map { mutation in
            guard case .elementAdd(let add) = mutation,
                  case .dopeEntity(let payload) = add.payload,
                  let center = codeCenters[payload.entityCode] else { return mutation }
            return .elementAdd(DiagramElementAdd(
                clientRef: add.clientRef, parentElementUuid: add.parentElementUuid,
                parentClientRef: add.parentClientRef, code: add.code, name: add.name,
                description: add.description, sortOrder: add.sortOrder,
                centerX: center.x, centerY: center.y,
                elementZ: add.elementZ, scale: add.scale, payload: add.payload))
        }
        let fresh = Self.emptyTree(id: id)
        do {
            let scaffolded = try DiagramTreeReducer.apply(
                mutations, to: fresh, expectedRevision: nil, minting: LiveDiagramMinting())
            // The user's drawn layers are NOT dope-derived — re-attach them
            // (identities intact) so a dope reload never deletes drawings.
            let preservedLayers = tree.elements.filter { node in
                if case .drawingLayer = node.payload { return true }
                return false
            }
            let newTree = DiagramTree(
                identity: scaffolded.identity, tier: scaffolded.tier,
                projectUuid: scaffolded.projectUuid,
                instanceUuid: scaffolded.instanceUuid,
                sessionUuid: scaffolded.sessionUuid,
                promptUuid: scaffolded.promptUuid,
                code: scaffolded.code, name: scaffolded.name,
                description: scaffolded.description,
                gmccDiagramPath: scaffolded.gmccDiagramPath,
                revision: scaffolded.revision,
                elements: scaffolded.elements + preservedLayers)
            // The tree was built OUTSIDE the box, so the box must be
            // authoritative BEFORE the session rebases onto the new revision
            // — strictly ordered inside one task, never detached.
            Task {
                await box.replace(newTree)
                adopt(newTree)
            }
        } catch {
            // A scaffold failure leaves the last good tree in place; the
            // reducer is parity-tested, so this is a should-never path.
            assertionFailure("diagram scaffold failed: \(error)")
        }
    }

    /// Record every entity card's current authored center by entity code.
    private func rememberCenters() {
        for element in tree.elements {
            guard case .dopeScopePersistenceLayer = element.payload else { continue }
            for child in element.children {
                if case .dopeEntity(let payload) = child.payload {
                    codeCenters[payload.entityCode] =
                        CGPoint(x: child.base.centerX, y: child.base.centerY)
                }
            }
        }
    }

    // MARK: - Adopt / filter / appearance

    /// The ONE place a new tree becomes visible: adopt it, rebase the edit
    /// session's CAS gate onto its revision, resolve once, re-project the
    /// filter.
    private func adopt(_ newTree: DiagramTree) {
        tree = newTree
        editSession.rebase(revision: newTree.revision)
        fullResolved = DiagramResolver.resolve(newTree, dope: dopeContext,
                                               environment: environment)
        resolved = DiagramDomainFilter.apply(domainFilter, to: fullResolved)
        generation += 1
        if case .dopePreview = id.source { rememberCenters() }
    }

    /// Multi-pill filter change — a projection of the existing resolve, so no
    /// write, no re-resolve, and no re-mint of anything.
    func setDomainFilter(_ domains: Set<String>) {
        guard domains != domainFilter else { return }
        domainFilter = domains
        resolved = DiagramDomainFilter.apply(domainFilter, to: fullResolved)
        // Same signal a content change raises: the screen drops a selection
        // or drag freeze pointing at a now-hidden element.
        generation += 1
    }

    /// O(1) appearance flip — the resolver never reads colorScheme, so a
    /// scheme swap needs no re-resolve (and no A* re-run).
    func reskin(_ scheme: ColorScheme) {
        let target: DiagramRenderEnvironment.ColorScheme = scheme == .dark ? .dark : .light
        guard target != colorScheme else { return }
        colorScheme = target
        fullResolved = fullResolved.reskinned(target)
        resolved = resolved.reskinned(target)
    }

    // MARK: - Writes

    /// Gesture-end commit. A failed flush against a saved diagram is almost
    /// always a revision CAS miss (another window committed), so re-read
    /// rather than leaving the canvas pinned to a revision the db has left
    /// behind — the staged prefix is already discarded by the session.
    func flush() async {
        do {
            try await editSession.flush()
        } catch {
            editSession.discard()
            if case .saved = id.source { await reloadDiagram() }
        }
    }

    // MARK: - Lookups

    /// The lazily-created top-level drawing layer, if one exists yet.
    var drawingLayer: DiagramElementNode? {
        tree.elements.first { node in
            if case .drawingLayer = node.payload { return true }
            return false
        }
    }

    func node(uuid: String) -> DiagramElementNode? {
        DiagramTreeReducer.findNode(uuid, in: tree.elements)
    }

    /// The parent of `uuid`, nil for a top-level element. A connector's
    /// legality is a statement about parentage (its target must be a peer of
    /// its own parent), so the screen needs to ask.
    func parentUuid(of uuid: String) -> String? {
        func walk(_ nodes: [DiagramElementNode], parent: String?) -> String?? {
            for node in nodes {
                if node.identity.uuid == uuid { return .some(parent) }
                if let found = walk(node.children, parent: node.identity.uuid) { return found }
            }
            return nil
        }
        return walk(tree.elements, parent: nil) ?? nil
    }

    /// The highest top-level elementZ (a new drawing layer must paint above
    /// the scope).
    var maxTopLevelZ: Double {
        tree.elements.map(\.base.elementZ).max() ?? 0
    }
}

/// Diagram tools. `select` is the only tool that can yield a `.move` intent —
/// draw tools structurally disable node drag (the locked decision); trackpad
/// pan keeps flowing through the scroll bridge in every tool.
///
/// rect/line/text were view-layer tools only and were retired for the UML
/// node vocabulary (Insert Node) — their payloads and renderers live on, so
/// existing diagrams keep drawing.
enum DiagramTool: String, CaseIterable, Identifiable, Hashable {
    case select, freehand, eraser, connector

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .freehand: "scribble"
        case .eraser: "eraser"
        case .connector: "arrow.triangle.branch"
        }
    }
    var help: String {
        switch self {
        case .select: "Click to select, drag to move a card — drag empty space to pan"
        case .freehand: "Draw freehand on the drawing layer"
        case .eraser: "Drag over strokes and shapes to erase them"
        case .connector: "Drag from one card to a sibling card to connect them"
        }
    }
}

/// The VIEW-STATE half: everything a gesture sample may touch. Writing here
/// can never re-resolve — `DiagramWorkspace.resolved` is not reachable from
/// these code paths.
@Observable @MainActor
final class DiagramViewState {
    var viewport = DiagramViewport()
    var tool: DiagramTool = .select
    var selection = DiagramSelectionState()
    var searchText = ""

    /// Freeze-during-drag: set at the first `.move` sample, cleared after the
    /// gesture-end flush lands. The scene renders `frozen` while non-nil.
    struct DragDraft {
        let elementUuid: String
        let frozen: ResolvedDiagram
        let frame: CGRect
        var delta: CGSize = .zero
    }
    var dragDraft: DragDraft?

    /// In-progress freehand/connector draft, diagram space.
    struct DrawDraft {
        let tool: DiagramTool
        let anchor: CGPoint
        var current: CGPoint
        /// Freehand only: every sample since pointer-down, decimated once on
        /// pointer-up.
        var points: [CGPoint] = []
    }
    var drawDraft: DrawDraft?

    /// Eraser accumulation: every stroke/shape the drag has passed over,
    /// dimmed live through the selection channel and deleted in ONE batch at
    /// gesture end (nothing stages until pointer-up).
    var erasedUuids: Set<String> = []
}
