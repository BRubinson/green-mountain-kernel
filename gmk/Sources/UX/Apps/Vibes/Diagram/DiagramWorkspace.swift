import SwiftUI
import Observation

/// Window-lifetime diagram state, keyed by `DiagramWindowID.workspaceKey` — the DIAGRAM's
/// identity (its uuid when saved, owner+scope for a preview), not the session's.
///
/// Held as `@State` on `GMVibesWindow` above the `.id(nav.route)` boundary and injected with
/// `.environment` — the exact seam `DrawingsStore` occupied — so viewport, selection and any
/// non-persisted canvas survive in-window navigation and die with the window. Deliberately NOT
/// SessionScopeCache (its grace list would resurrect a closed window's workspace).
@Observable @MainActor
final class DiagramWorkspaceStore {
    /// @ObservationIgnored makes create-or-get legal from a view body (the DrawingsStore
    /// rule): a TRACKED dictionary would register a read dependency and then write inside the
    /// same tracking scope.
    ///
    /// Each DiagramWorkspace is the real observable unit.
    @ObservationIgnored private var workspaces: [String: DiagramWorkspace] = [:]

    /// Returns the workspace for the given diagram window ID, creating it if needed.
    ///
    /// - Parameter id: The diagram window identifier.
    /// - Returns: The workspace keyed by the ID.
    func workspace(for id: DiagramWindowID) -> DiagramWorkspace {
        if let existing = workspaces[id.workspaceKey] { return existing }
        let fresh = DiagramWorkspace(id: id)
        workspaces[id.workspaceKey] = fresh
        return fresh
    }
}

/// The MODEL half of the diagram screen; `DiagramViewState` is the view-state half.
///
/// The split makes the freeze-during-drag guarantee structural: `resolved` is written only by
/// `adopt` / `reproject` / `reskin`, so a drag sample writes view state alone; per-property
/// observation prevents per-sample re-resolve.
///
/// A `.saved` source is a db diagram loaded via DIAGRAM_GET, written via DIAGRAM_BATCH_APPLY.
/// A `.dopePreview` is scaffolded in memory and committed locally, never reaching the db.
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

    /// The single write funnel: stage/restage during a gesture, one flush at gesture end.
    ///
    /// Assigned by `init` for both sources, so it is non-nil for the workspace's whole life.
    private(set) var editSession: DiagramEditSession?

    /// The dope tree the cards are drawn from (search and the domain pills run over this).
    ///
    /// The FIRST bound scope when a canvas binds several.
    private(set) var dope: DopeGetResponse?
    /// Multi-pill domain filter: empty = all domains shown.
    ///
    /// A RENDER-TIME filter (see DiagramDomainFilter) — never a tree rebuild.
    private(set) var domainFilter: Set<String> = []

    /// The filter-blind resolve.
    ///
    /// Stored so a pill toggle re-projects instead of re-resolving (which would re-run the A* edge routing).
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

    /// Creates a workspace for the given diagram source.
    ///
    /// - Parameter id: The diagram window identifier specifying the source and owner.
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
                baseRevision: nil
            )
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
                baseRevision: 0
            )
        }
    }

    /// Creates an empty diagram tree for the given window ID.
    ///
    /// - Parameter id: The diagram window identifier.
    /// - Returns: A new empty diagram tree.
    private static func emptyTree(id: DiagramWindowID) -> DiagramTree {
        let now = ISO8601DateFormatter().string(from: Date())
        let session = id.session?.sessionUUID.wireString
        return DiagramTree(
            identity: DopeNodeIdentity(
                uuid: id.savedDiagramUuid ?? UUID().uuidString.lowercased(),
                version: 0,
                createdAt: now,
                updatedAt: now
            ),
            tier: session == nil ? "PROJECT" : "SESSION",
            projectUuid: id.projectUuid,
            instanceUuid: nil,
            sessionUuid: session,
            promptUuid: nil,
            code: id.previewScopeCode ?? id.name,
            name: id.name,
            description: "",
            gmccDiagramPath: nil,
            revision: 0,
            elements: []
        )
    }

    private var environment: DiagramRenderEnvironment {
        DiagramRenderEnvironment(colorScheme: colorScheme)
    }

    private var dopeContext: DiagramDopeContext {
        DiagramDopeContext(entries: dopeEntries)
    }

    // MARK: - Loading

    /// Loads the diagram and applies the color scheme.
    ///
    /// Idempotent: a second call re-reads rather than re-scaffolding, so a generation bump
    /// or a re-entered screen never resets a canvas the user has moved.
    ///
    /// - Parameter scheme: The color scheme to apply.
    func load(scheme: ColorScheme) async {
        colorScheme = scheme == .dark ? .dark : .light
        switch id.source {
        case .saved:
            await reloadDiagram()
        case .dopePreview(let code):
            await loadPreview(scopeCode: code)
        }
    }

    /// Re-reads the diagram row and its bound dope trees.
    ///
    /// Called on DIAGRAM_CHANGE wake or post-flush conflict recovery.
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

    /// DOPE_CHANGE wake.
    ///
    /// A SAVED diagram only RE-RESOLVES: its cards are rows, so a new dope entity does not
    /// silently mint one — the scaffold is a create-time act. A preview re-scaffolds, since its
    /// whole content is derived and nothing is persisted to lose.
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

    /// Fetches one dope tree per bound scope code in the diagram.
    ///
    /// Bindings resolve through the diagram's own owner chain — a session/prompt read for
    /// session-owned diagrams, the project ladder for a project-tier diagram.
    ///
    /// - Parameter response: The diagram get response containing the tree and bindings.
    private func loadDopeEntries(for response: DiagramGetResponse) async {
        var entries: [String: DiagramDopeContext.Entry] = [:]
        var primary: DopeGetResponse?
        for code in Self.boundScopeCodes(in: response.tree.elements) {
            guard
                let dope = try? await fetchDope(
                    sessionUuid: response.tree.sessionUuid,
                    promptUuid: response.tree.promptUuid,
                    code: code,
                    // The TREE's project, not the route payload's: the row is
                    // authoritative about its own owner chain, and a promotion
                    // can have moved it since the route was built.
                    projectUuid: response.tree.projectUuid
                )
            else {
                // A code matching nothing is the LEGAL ghost state, not an
                // error: the resolver renders an absent scope card.
                continue
            }
            entries[code] = DiagramDopeContext.Entry(
                tree: dope.tree,
                resolvedVia: dope.resolvedVia
            )
            if primary == nil { primary = dope }
        }
        dopeEntries = entries
        dope = primary
    }

    /// Fetches a dope scope tree by code, resolving through owner chains.
    ///
    /// - Parameters:
    ///   - sessionUuid: The session UUID for session-scoped lookups; nil for project scope.
    ///   - promptUuid: The prompt UUID when looking up session scope entries.
    ///   - code: The dope scope code to fetch.
    ///   - projectUuid: The project UUID for project-scoped lookups; defaults to window's project.
    /// - Returns: The dope scope tree response.
    /// - Throws: Any error from the daemon service.
    private func fetchDope(
        sessionUuid: String?,
        promptUuid: String?,
        code: String?,
        projectUuid: String? = nil
    ) async throws -> DopeGetResponse {
        if let sessionUuid {
            return try await service.dopeGet(
                sessionUuid: sessionUuid,
                promptUuid: promptUuid,
                code: code
            )
        }
        return try await service.dopeGet(
            projectUuid: projectUuid ?? id.projectUuid,
            code: code
        )
    }

    /// Extracts the unique dope scope codes from diagram elements.
    ///
    /// - Parameter elements: The diagram element nodes to scan.
    /// - Returns: An array of unique dope scope codes found in the elements.
    private static func boundScopeCodes(in elements: [DiagramElementNode]) -> [String] {
        var codes: [String] = []
        for element in elements {
            if case .dopeScopePersistenceLayer(let payload) = element.payload,
                !codes.contains(payload.dopeScopeCode)
            {
                codes.append(payload.dopeScopeCode)
            }
        }
        return codes
    }

    // MARK: - Preview scaffold

    /// Loads a dope scope and optionally scaffolds a diagram preview from it.
    ///
    /// Reads the dope scope and lays it out via `DopeCanvasLayout`, the same layout
    /// the CLI generator uses. If not yet loaded or rescaffolding, applies the layout
    /// with the parity-tested reducer.
    ///
    /// - Parameters:
    ///   - scopeCode: The dope scope code to load.
    ///   - rescaffold: Whether to rebuild the diagram tree from the dope scope.
    private func loadPreview(scopeCode: String?, rescaffold: Bool = false) async {
        do {
            let response = try await fetchDope(
                sessionUuid: id.session?.sessionUUID.wireString,
                promptUuid: nil,
                code: scopeCode
            )
            dopeEntries = [
                response.tree.body.code: DiagramDopeContext.Entry(
                    tree: response.tree,
                    resolvedVia: response.resolvedVia
                )
            ]
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

    /// Builds a diagram tree from a dope scope tree and preserves user drawings.
    ///
    /// - Parameter dopeTree: The dope scope tree to scaffold from.
    private func scaffoldPreview(from dopeTree: DopeScopeTree) {
        guard let box else { return }
        // A re-scaffold re-mints every element uuid — anything staged against
        // the old tree (a drag in flight when a dope event lands) is poison
        // and must be dropped BEFORE the swap.
        editSession?.discard()
        rememberCenters()
        var mutations = DopeCanvasLayout.mutations(for: dopeTree)
        // Carryover: a card whose entity code was placed before keeps its
        // center across reloads.
        mutations = mutations.map { mutation in
            guard case .elementAdd(let add) = mutation,
                case .dopeEntity(let payload) = add.payload,
                let center = codeCenters[payload.entityCode]
            else { return mutation }
            return .elementAdd(
                DiagramElementAdd(
                    payload: add.payload,
                    clientRef: add.clientRef,
                    parentElementUuid: add.parentElementUuid,
                    parentClientRef: add.parentClientRef,
                    code: add.code,
                    name: add.name,
                    description: add.description,
                    sortOrder: add.sortOrder,
                    centerX: center.x,
                    centerY: center.y,
                    elementZ: add.elementZ,
                    scale: add.scale
                )
            )
        }
        let fresh = Self.emptyTree(id: id)
        do {
            let scaffolded = try DiagramTreeReducer.apply(
                mutations,
                to: fresh,
                minting: LiveDiagramMinting(),
                expectedRevision: nil
            )
            // The user's drawn layers are NOT dope-derived — re-attach them
            // (identities intact) so a dope reload never deletes drawings.
            let preservedLayers = tree.elements.filter { node in
                if case .drawingLayer = node.payload { return true }
                return false
            }
            let newTree = DiagramTree(
                identity: scaffolded.identity,
                tier: scaffolded.tier,
                projectUuid: scaffolded.projectUuid,
                instanceUuid: scaffolded.instanceUuid,
                sessionUuid: scaffolded.sessionUuid,
                promptUuid: scaffolded.promptUuid,
                code: scaffolded.code,
                name: scaffolded.name,
                description: scaffolded.description,
                gmccDiagramPath: scaffolded.gmccDiagramPath,
                revision: scaffolded.revision,
                elements: scaffolded.elements + preservedLayers
            )
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

    /// Makes a new tree visible and updates all derived state.
    ///
    /// The sole place where a tree becomes visible: adopts it, rebases the edit
    /// session's CAS gate onto its revision, resolves once, and re-projects the
    /// domain filter.
    ///
    /// - Parameter newTree: The tree to adopt and make visible.
    private func adopt(_ newTree: DiagramTree) {
        tree = newTree
        editSession?.rebase(revision: newTree.revision)
        fullResolved = DiagramResolver.resolve(
            newTree,
            dope: dopeContext,
            environment: environment
        )
        resolved = DiagramDomainFilter.apply(domainFilter, to: fullResolved)
        generation += 1
        if case .dopePreview = id.source { rememberCenters() }
    }

    /// Applies a domain filter by re-projecting the existing resolve.
    ///
    /// Changes the visible domains without writing, re-resolving, or re-minting elements.
    ///
    /// - Parameter domains: The set of domain codes to show; empty means all.
    func setDomainFilter(_ domains: Set<String>) {
        guard domains != domainFilter else { return }
        domainFilter = domains
        resolved = DiagramDomainFilter.apply(domainFilter, to: fullResolved)
        // Same signal a content change raises: the screen drops a selection
        // or drag freeze pointing at a now-hidden element.
        generation += 1
    }

    /// Applies a color scheme without re-resolving or re-routing.
    ///
    /// Changes appearance in O(1) time since the resolver does not read color scheme.
    ///
    /// - Parameter scheme: The color scheme to apply.
    func reskin(_ scheme: ColorScheme) {
        let target: DiagramRenderEnvironment.ColorScheme = scheme == .dark ? .dark : .light
        guard target != colorScheme else { return }
        colorScheme = target
        fullResolved = fullResolved.reskinned(target)
        resolved = resolved.reskinned(target)
    }

    // MARK: - Writes

    /// Gesture-end commit.
    ///
    /// A failed flush against a saved diagram is almost always a revision CAS miss
    /// (another window committed), so re-read rather than leaving the canvas pinned to a
    /// revision the db has left behind — the staged prefix is already discarded by the session.
    func flush() async {
        do {
            try await editSession?.flush()
        } catch {
            editSession?.discard()
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

    /// Returns the diagram element node with the given UUID.
    ///
    /// - Parameter uuid: The element UUID to find.
    /// - Returns: The element node, or nil if not found.
    func node(uuid: String) -> DiagramElementNode? {
        DiagramTreeReducer.findNode(uuid, in: tree.elements)
    }

    /// Returns the parent UUID of the given element.
    ///
    /// A connector's legality depends on parentage, so the screen needs to ask the parent
    /// to determine whether the target is a valid peer.
    ///
    /// - Parameter uuid: The element UUID whose parent to find.
    /// - Returns: The parent UUID, or nil for a top-level element.
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

/// The VIEW-STATE half: everything a gesture sample may touch.
///
/// Writing here can never re-resolve — `DiagramWorkspace.resolved` is not reachable from
/// these code paths.
@Observable @MainActor
final class DiagramViewState {
    var viewport = DiagramViewport()
    var tool: DiagramTool = .select
    var selection = DiagramSelectionState()
    var searchText = ""

    /// Freeze-during-drag: set at the first `.move` sample, cleared after the gesture-end flush lands.
    ///
    /// The scene renders `frozen` while non-nil.
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
