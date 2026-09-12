import SwiftUI
import AppKit
import GMCCDaemonKit

/// The full-window diagram editor (`Route.diagram`): a diagram rendered on
/// the kit's slot-rich DiagramUI components.
///
/// PERSISTENCE follows the route payload, not this screen: a `.saved`
/// workspace writes every gesture through DiagramEditSession →
/// DaemonDiagramCommitter → DIAGRAM_BATCH_APPLY, a `.dopePreview` one through
/// the local reducer and nowhere else. The screen is identical either way —
/// that is the point of the committer seam.
///
/// COORDINATE COMPOSITION (the load-bearing decision): pan rides the kit's
/// diagram-space `offset:` parameter (applied INSIDE each Canvas and on each
/// .position — the ffc9bb5-safe path; the `.offset` modifier is BANNED
/// here), zoom rides `.scaleEffect(zoom, anchor: .topLeading)`. That
/// composes to screen = diagram·zoom + viewport.offset — exactly
/// `DiagramViewport.toScreen`, so the salvaged viewport stays the single
/// screen↔diagram truth.
struct DiagramScreen: View {
    @Environment(DaemonConnectionModel.self) private var daemon
    @Environment(DiagramWorkspaceStore.self) private var workspaces
    @Environment(\.colorScheme) private var colorScheme
    let windowID: DiagramWindowID

    @State private var viewState = DiagramViewState()
    @State private var sink = DiagramScrollBridge.Sink()
    @State private var dragStartLocation: CGPoint?
    @State private var dragIntent: DragIntent?
    @State private var zoomBase: CGFloat?
    @State private var lastPan: CGSize = .zero
    @State private var hostSize: CGSize = .zero
    @State private var didInitialFit = false
    @State private var showDopeScopeSheet = false

    private var workspace: DiagramWorkspace {
        workspaces.workspace(for: windowID)
    }

    /// Decided ONCE at gesture start (the ported DrawingCanvasView
    /// discipline) — re-deciding per frame lets a card slide out from under
    /// the cursor and flips a move into a pan mid-drag.
    private enum DragIntent {
        case pan
        case move(uuid: String, node: DiagramElementNode, grab: CGPoint)
        case draw(tool: DiagramTool, anchor: CGPoint)
        /// Connector tool: the element the drag STARTED on. The target is
        /// whatever the drag ends over, decided at pointer-up.
        case connect(fromUuid: String, anchor: CGPoint)
        /// Eraser: accumulate hits per sample, commit ONE delete batch at
        /// pointer-up.
        case erase
    }

    var body: some View {
        ScreenScaffold(title: "Diagram · \(windowID.name)",
                       subtitle: subtitle) {
            content
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DiagramToolStrip(workspace: workspace, viewState: viewState,
                                 onCenter: center(on:), onFit: fit,
                                 onOrganize: organize, onCopy: copyToClipboard,
                                 onInsertNode: insertNode(_:),
                                 onAddDopeScope: { showDopeScopeSheet = true })
            }
        }
        .sheet(isPresented: $showDopeScopeSheet) {
            DiagramDopeScopeSheet(workspace: workspace)
        }
        .task(id: daemon.generation) {
            await workspace.load(scheme: colorScheme)
            attemptInitialFit()
            // Two independent wakes, hoisted on MainActor before the group:
            // the diagram's own row (another window committing to it) and the
            // dope tree its cards are drawn from.
            let diagramStream = windowID.savedDiagramUuid.map {
                daemon.hub.stream(for: .diagram($0))
            }
            var dopeStream: AsyncStream<Void>?
            if let sessionUuid = windowID.session?.sessionUUID.wireString {
                dopeStream = daemon.hub.stream(for: .dope(sessionUuid))
            }
            let workspace = self.workspace
            await withTaskGroup(of: Void.self) { group in
                if let diagramStream {
                    group.addTask {
                        for await _ in diagramStream { await workspace.reloadDiagram() }
                    }
                }
                if let dopeStream {
                    group.addTask {
                        for await _ in dopeStream {
                            // Debounced: a bot's tree build writes N nodes,
                            // and each one would otherwise be a full reload.
                            try? await Task.sleep(for: .milliseconds(300))
                            await workspace.reloadDope()
                        }
                    }
                }
            }
        }
        // A reload or a filter change can retire an element: drop any
        // selection or drag freeze that now points at something not drawn.
        .onChange(of: workspace.generation) {
            if let selected = viewState.selection.selectedElementUuid,
               workspace.resolved.element(uuid: selected) == nil {
                clearSelection()
            }
            if let draft = viewState.dragDraft,
               workspace.resolved.element(uuid: draft.elementUuid) == nil {
                viewState.dragDraft = nil
            }
            attemptInitialFit()
        }
        .onChange(of: colorScheme) { _, newScheme in
            workspace.reskin(newScheme)   // O(1) — no A* re-run
        }
    }

    private var subtitle: String? {
        if let error = workspace.loadError { return error }
        switch windowID.source {
        case .saved:
            return workspace.dope.map { "dope · \($0.tree.body.code)" }
        case .dopePreview(let code):
            // Say so out loud: a preview looks exactly like the real editor.
            let scope = code ?? workspace.dope?.tree.body.code ?? "dope"
            return "\(scope) · preview (not saved)"
        }
    }

    /// The first fit needs BOTH a loaded tree and a real host size — either
    /// can arrive first (the load vs GeometryReader), so both paths call this
    /// and the flag flips only once it actually ran.
    private func attemptInitialFit() {
        guard !didInitialFit, workspace.loaded, hostSize != .zero else { return }
        didInitialFit = true
        fit()
    }

    @ViewBuilder
    private var content: some View {
        if workspace.loaded {
            canvasHost
        } else if let error = workspace.loadError {
            ContentUnavailableView("Diagram Unavailable", systemImage: "bolt.slash",
                                   description: Text(error))
        } else {
            ProgressView("Loading diagram…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - The viewport host

    private var canvasHost: some View {
        // Value snapshots read HERE, in the tracked body scope (renderer
        // closures and gesture callbacks are not tracked): the frozen
        // resolved during a drag, the live one otherwise.
        let resolved = viewState.dragDraft?.frozen ?? workspace.resolved
        let viewport = viewState.viewport

        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The screen owns its background (DiagramSceneView paints
                // none) — live appearance, not the baked screenshot color.
                Color(nsColor: .textBackgroundColor).ignoresSafeArea()
                DiagramSceneView(resolved: resolved, offset: sceneOffset(viewport)) {
                    EmptyView()
                } overlay: {
                    DiagramDraftOverlay(dragDraft: viewState.dragDraft,
                                        drawDraft: viewState.drawDraft,
                                        offset: sceneOffset(viewport))
                }
                .environment(\.diagramSelection, effectiveSelection)
                .scaleEffect(viewport.zoom, anchor: .topLeading)
            }
            .contentShape(Rectangle())
            .background { DiagramScrollBridge(sink: sink) }
            .gesture(canvasGesture)
            // simultaneous, not .gesture: a pan in flight must never block a pinch.
            .simultaneousGesture(magnify)
            .onAppear {
                hostSize = proxy.size
                attemptInitialFit()
                sink.onPan = { delta in
                    viewState.viewport.offset.width += delta.width
                    viewState.viewport.offset.height += delta.height
                }
                sink.onZoom = { factor, anchor in
                    viewState.viewport.zoom(
                        to: viewState.viewport.zoom * factor, anchor: anchor)
                }
            }
            .onChange(of: proxy.size) { _, newSize in hostSize = newSize }
        }
        .clipped()
    }

    /// Pan expressed in DIAGRAM space for the kit's offset parameter:
    /// (diagram + offset/zoom)·zoom = diagram·zoom + offset == toScreen.
    private func sceneOffset(_ viewport: DiagramViewport) -> CGSize {
        CGSize(width: viewport.offset.width / viewport.zoom,
               height: viewport.offset.height / viewport.zoom)
    }

    /// The dragged card dims in place while its ghost tracks the cursor;
    /// eraser-swept ink dims live until the delete batch lands.
    private var effectiveSelection: DiagramSelectionState {
        var selection = viewState.selection
        if let draft = viewState.dragDraft {
            selection.dimmedElementUuids.insert(draft.elementUuid)
        }
        selection.dimmedElementUuids.formUnion(viewState.erasedUuids)
        return selection
    }

    // MARK: - Gestures (the five ported disciplines)

    private var canvasGesture: some Gesture {
        // minimumDistance MUST be 0: the default (10) silently kills
        // click-to-select.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A different startLocation means a NEW drag: reset whatever a
                // CANCELLED predecessor left behind (its onEnded never ran) —
                // including its staged mutations on the edit session.
                if dragStartLocation != value.startLocation {
                    resetDrafts(discardStaged: true)
                    dragStartLocation = value.startLocation
                }
                // Convert AT CAPTURE: a trackpad pan mid-drag changes the
                // viewport; diagram-space points stay welded to the diagram.
                let p = viewState.viewport.canvasPoint(value.location)
                let intent = dragIntent ?? begin(at: p)
                switch intent {
                case .move(let uuid, let node, let grab):
                    let delta = CGSize(width: p.x - grab.x, height: p.y - grab.y)
                    if viewState.dragDraft == nil {
                        guard let element = workspace.resolved.element(uuid: uuid) else { break }
                        viewState.dragDraft = DiagramViewState.DragDraft(
                            elementUuid: uuid, frozen: workspace.resolved,
                            frame: element.frame)
                    }
                    viewState.dragDraft?.delta = delta
                    // Restage ONE coalesced elementUpdate per sample — the
                    // divisor arithmetic lives in the kit.
                    if let element = viewState.dragDraft.flatMap({
                        $0.frozen.element(uuid: uuid) }) {
                        workspace.editSession.restage(DiagramDrag.moveMutation(
                            node: node, resolved: element, by: delta))
                    }
                case .draw(let tool, let anchor):
                    if viewState.drawDraft == nil {
                        viewState.drawDraft = DiagramViewState.DrawDraft(
                            tool: tool, anchor: anchor, current: p, points: [anchor])
                    }
                    viewState.drawDraft?.current = p
                    // Freehand keeps every sample; RDP runs ONCE on
                    // pointer-up, where it can see the whole stroke.
                    if tool == .freehand { viewState.drawDraft?.points.append(p) }
                case .connect(_, let anchor):
                    viewState.drawDraft = DiagramViewState.DrawDraft(
                        tool: .connector, anchor: anchor, current: p)
                case .erase:
                    // includeInk opts strokes/shapes into hit testing; the
                    // launch eraser is restricted to exactly those two kinds
                    // (never layers, cards, or scope containers).
                    if case .element(let element)? = workspace.resolved.hitTest(
                        at: p, edgeTolerance: 6 / viewState.viewport.zoom,
                        includeInk: true) {
                        switch element.kind {
                        case .stroke, .shape:
                            viewState.erasedUuids.insert(element.uuid)
                        default:
                            break
                        }
                    }
                case .pan:
                    viewState.viewport.offset.width += value.translation.width - lastPan.width
                    viewState.viewport.offset.height += value.translation.height - lastPan.height
                    lastPan = value.translation
                }
            }
            .onEnded { _ in
                switch dragIntent {
                case .move:
                    // Flush + ONE re-resolve (inside the commit callback);
                    // clear the freeze only after the new resolved lands.
                    Task {
                        await workspace.flush()
                        viewState.dragDraft = nil
                    }
                case .draw(let tool, let anchor):
                    if let draft = viewState.drawDraft {
                        commitDrawing(tool: tool, from: anchor, draft: draft)
                    }
                case .connect(let fromUuid, _):
                    if let draft = viewState.drawDraft {
                        commitConnector(from: fromUuid, to: draft.current)
                    }
                case .erase:
                    commitErase()
                case .pan, nil:
                    break
                }
                resetDrafts(discardStaged: false)
            }
    }

    private func resetDrafts(discardStaged: Bool) {
        if discardStaged {
            // Stale staged mutations from a cancelled drag must never ride
            // into the next flush.
            workspace.editSession.discard()
            viewState.dragDraft = nil
            // A cancelled erase staged nothing — only the dim set needs
            // clearing. A COMMITTED one clears after its flush lands, so the
            // swept ink never flashes back between pointer-up and adopt.
            viewState.erasedUuids = []
        }
        viewState.drawDraft = nil
        dragIntent = nil
        lastPan = .zero
    }

    private func begin(at p: CGPoint) -> DragIntent {
        let intent: DragIntent
        switch viewState.tool {
        case .freehand:
            intent = .draw(tool: .freehand, anchor: p)
        case .eraser:
            intent = .erase
        case .connector:
            // A connector hangs off the element it starts on; starting in
            // empty space has nothing to hang it from, so that pans.
            if case .element(let element)? = workspace.resolved.hitTest(
                at: p, edgeTolerance: 6 / viewState.viewport.zoom),
               workspace.node(uuid: element.uuid) != nil {
                select(element.uuid)
                intent = .connect(fromUuid: element.uuid, anchor: p)
            } else {
                intent = .pan
            }
        case .select:
            // Tolerance constant in SCREEN points at any zoom.
            let hit = workspace.resolved.hitTest(
                at: p, edgeTolerance: 6 / viewState.viewport.zoom)
            switch hit {
            case .element(let element):
                switch element.kind {
                // A text box or UML node is draggable for the same reason a
                // card is: it is a bounded thing you positioned by hand.
                case .entityCard, .absentEntity, .text, .umlNode:
                    if let node = workspace.node(uuid: element.uuid) {
                        select(element.uuid)
                        intent = .move(uuid: element.uuid, node: node, grab: p)
                    } else {
                        intent = .pan
                    }
                // A connector has no position of its own — it follows its
                // endpoints — so grabbing one pans the canvas.
                case .scopeCard, .absentScope, .layer, .stroke, .shape, .connector:
                    clearSelection()
                    intent = .pan
                }
            case .edge, nil:
                clearSelection()
                intent = .pan
            }
        }
        dragIntent = intent
        return intent
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // value.magnification is CUMULATIVE from gesture start:
                // multiply the gesture-start baseline, never compound.
                let base: CGFloat
                if let zoomBase {
                    base = zoomBase
                } else {
                    base = viewState.viewport.zoom
                    zoomBase = base
                }
                viewState.viewport.zoom(to: base * value.magnification,
                                        anchor: value.startLocation)
            }
            .onEnded { _ in zoomBase = nil }
    }

    // MARK: - Selection / centering

    private func select(_ uuid: String) {
        viewState.selection = DiagramSelectionState(
            selectedElementUuid: uuid, highlightedElementUuids: [uuid])
    }

    private func clearSelection() {
        viewState.selection = DiagramSelectionState()
    }

    /// Center a diagram-space point (search jump / selection).
    private func center(on point: CGPoint) {
        guard hostSize != .zero else { return }
        withAnimation(.snappy(duration: 0.2)) {
            viewState.viewport.center(on: point, in: hostSize)
        }
    }

    /// Fit the whole content into the host.
    private func fit() {
        let bounds = workspace.resolved.contentBounds.insetBy(dx: -48, dy: -48)
        guard hostSize != .zero, bounds.width > 0, bounds.height > 0 else { return }
        let zoom = min(min(hostSize.width / bounds.width,
                           hostSize.height / bounds.height), 1)
        viewState.viewport.zoom = max(zoom, DiagramViewport.zoomRange.lowerBound)
        viewState.viewport.center(
            on: CGPoint(x: bounds.midX, y: bounds.midY), in: hostSize)
    }

    // MARK: - Draw mode

    /// Commit a freehand stroke through the shared drawing-layer funnel.
    private func commitDrawing(tool: DiagramTool, from anchor: CGPoint,
                               draft: DiagramViewState.DrawDraft) {
        guard tool == .freehand,
              let add = freehandAdd(draft: draft) else { return }
        stageOnDrawingLayer(center: add.center, payload: add.payload)
        flushSelectingNewElement()
    }

    /// ONE batch that lazily creates the top-level drawing_layer (high
    /// sibling z) via clientRef + parentClientRef when it doesn't exist yet —
    /// layer and first element land atomically, exactly what in-batch
    /// parenting exists for.
    private func stageOnDrawingLayer(center: CGPoint, payload: DiagramElementPayload) {
        let session = workspace.editSession!
        if let layer = workspace.drawingLayer {
            session.stage(.elementAdd(DiagramElementAdd(
                clientRef: Self.newElementRef,
                parentElementUuid: layer.identity.uuid,
                centerX: center.x, centerY: center.y,
                payload: payload)))
        } else {
            session.stage(.elementAdd(DiagramElementAdd(
                clientRef: "drawing_layer",
                elementZ: workspace.maxTopLevelZ + 10,
                payload: .drawingLayer(DrawingLayerPayload()))))
            session.stage(.elementAdd(DiagramElementAdd(
                clientRef: Self.newElementRef,
                parentClientRef: "drawing_layer",
                centerX: center.x, centerY: center.y,
                payload: payload)))
        }
    }

    /// The stroke payload + diagram-space center. Vertices are always
    /// ELEMENT-LOCAL (relative to that center) — the kit's storage contract.
    /// RDP once on pointer-up: a trackpad emits far more points than the
    /// curve needs, and every one of them costs storage and every later
    /// render.
    private func freehandAdd(draft: DiagramViewState.DrawDraft)
        -> (center: CGPoint, payload: DiagramElementPayload)?
    {
        guard draft.points.count >= 2 else { return nil }
        let xs = draft.points.map(\.x), ys = draft.points.map(\.y)
        let center = CGPoint(x: (xs.min()! + xs.max()!) / 2,
                             y: (ys.min()! + ys.max()!) / 2)
        let vertices = DiagramStrokeCodec.decimate(draft.points.map {
            DiagramVertex(x: $0.x - center.x, y: $0.y - center.y)
        })
        return (center, .drawingStroke(DrawingStrokePayload(
            tool: .pencil, strokeColor: "#e67326", strokeWidth: 2,
            vertices: vertices)))
    }

    /// Insert one UML node at the viewport center, parented under the (lazily
    /// created) drawing layer — the same funnel a drawn stroke rides.
    private func insertNode(_ kind: DiagramNodeKind) {
        let center = hostSize == .zero
            ? CGPoint.zero
            : viewState.viewport.canvasPoint(
                CGPoint(x: hostSize.width / 2, y: hostSize.height / 2))
        stageOnDrawingLayer(center: center, payload: .umlNode(UmlNodePayload(
            nodeKind: kind, width: 170, height: 100, markdown: "## Title")))
        flushSelectingNewElement()
    }

    /// Gesture-end erase: ONE batch of element_delete for everything the drag
    /// swept, CAS-gated per element on the version the tree holds. The dim
    /// set clears only after the flush lands so dead ink never flashes back.
    private func commitErase() {
        let uuids = viewState.erasedUuids
        guard !uuids.isEmpty else { return }
        let session = workspace.editSession!
        for uuid in uuids {
            guard let node = workspace.node(uuid: uuid) else { continue }
            session.stage(.elementDelete(DiagramElementDelete(
                elementUuid: uuid, expectedVersion: node.identity.version)))
        }
        Task {
            await workspace.flush()
            // Subtract exactly what THIS gesture committed — a blanket
            // clear here raced a second in-flight erase gesture and wiped
            // its sweep mid-drag.
            viewState.erasedUuids.subtract(uuids)
        }
    }

    /// Connect two elements. The connector is parented to the SOURCE and
    /// targets a PEER OF THAT PARENT — so the two ends must share a parent
    /// (two cards in one scope layer). Anything else is refused silently:
    /// the write path would reject it, and a validation error on a drag is
    /// noise, not information.
    private func commitConnector(from fromUuid: String, to point: CGPoint) {
        guard case .element(let target)? = workspace.resolved.hitTest(
                at: point, edgeTolerance: 6 / viewState.viewport.zoom),
              target.uuid != fromUuid,
              workspace.parentUuid(of: fromUuid) == workspace.parentUuid(of: target.uuid)
        else { return }
        let session = workspace.editSession!
        session.stage(.elementAdd(DiagramElementAdd(
            clientRef: Self.newElementRef,
            parentElementUuid: fromUuid,
            payload: .connector(ConnectorPayload(targetElementUuid: target.uuid)))))
        flushSelectingNewElement()
    }

    /// The clientRef every "the user just drew this" add carries.
    private static let newElementRef = "new_element"

    /// Commit, then select what was created. The WRITER mints the uuid — the
    /// daemon for a saved diagram, the reducer for a preview — so the
    /// clientRef the add carried is the only handle on the new row, and the
    /// commit outcome is where it comes back.
    private func flushSelectingNewElement() {
        Task {
            await workspace.flush()
            if let uuid = workspace.editSession.lastMintedUuids[Self.newElementRef] {
                select(uuid)
            }
        }
    }

    // MARK: - Organize / clipboard

    private func organize() {
        let mutations = DiagramOrganizer.organize(workspace.resolved,
                                                  tree: workspace.tree)
        guard !mutations.isEmpty else { return }
        let session = workspace.editSession!
        for mutation in mutations { session.stage(mutation) }
        Task { await workspace.flush() }
    }

    /// Copy the RENDERED diagram to the pasteboard — the screenshot framing
    /// view (content-derived bounds, baked background), not a window grab, so
    /// what lands on the clipboard is the whole canvas rather than whatever
    /// the viewport happened to be showing.
    private func copyToClipboard() {
        let canvas = DiagramCanvasView(resolved: workspace.resolved)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

/// The overlay slot's content: the drag ghost (dashed accent rect tracking
/// the cursor — a Canvas stroke, not a re-rendered card) and the in-progress
/// draw draft. Draws in DIAGRAM space at the scene's own offset, so it
/// inherits the outer `.scaleEffect` like every other layer.
private struct DiagramDraftOverlay: View {
    let dragDraft: DiagramViewState.DragDraft?
    let drawDraft: DiagramViewState.DrawDraft?
    let offset: CGSize

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: offset.width, y: offset.height)
            if let draft = dragDraft {
                let frame = draft.frame.offsetBy(dx: draft.delta.width,
                                                 dy: draft.delta.height)
                context.stroke(
                    Path(roundedRect: frame, cornerRadius: 6),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            if let draft = drawDraft {
                var path = Path()
                switch draft.tool {
                case .freehand:
                    path.addLines(draft.points)
                case .connector, .select, .eraser:
                    path.move(to: draft.anchor)
                    path.addLine(to: draft.current)
                }
                // Brand orange (RGBAColor.brandOrange) — matches the #e67326
                // the committed shape payload carries.
                context.stroke(path,
                               with: .color(Color(red: 0.9, green: 0.45, blue: 0.15)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
