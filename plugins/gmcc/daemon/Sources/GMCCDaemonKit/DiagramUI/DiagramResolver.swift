import CoreGraphics
import Foundation

/// The pure pre-pass that turns (DiagramTree + hydrated dope trees) into a
/// ready-to-draw `ResolvedDiagram`. Transforms, sibling z-order, dope
/// injection, `.absent` ghosts, FK edges, and deterministic colors are all
/// computed exactly ONCE here — views are dumb exhaustive switches, and the
/// binding/ghost/geometry tests target this type in plain XCTest with zero
/// SwiftUI.
///
/// Imports Foundation + CoreGraphics only. This file is deliberately outside
/// the `#if canImport(SwiftUI)` guard the view files carry.

/// Caller-assembled dope context: one hydrated tree per RESOLVED dope_scope
/// binding code (from DIAGRAM_GET's bindings + one DOPE_GET each). Codes the
/// caller could not resolve are simply absent — their elements ghost.
public struct DiagramDopeContext: Sendable {
    public struct Entry: Sendable {
        public let tree: DopeScopeTree
        /// "prompt" | "session_base" — surfaced on the scope card.
        public let resolvedVia: String

        public init(tree: DopeScopeTree, resolvedVia: String) {
            self.tree = tree
            self.resolvedVia = resolvedVia
        }
    }

    /// Keyed by dope scope code.
    public let entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }
}

public struct ResolvedDiagram: Sendable {
    /// Union of every drawn frame + edge, pre-padding — the screenshot
    /// viewport (content-derived, never a window guess).
    public let contentBounds: CGRect
    /// Painter-sorted ((elementZ, code) among siblings; depth-first global).
    public let topLevel: [ResolvedElement]
    /// FK edges between entity cards, computed in their own pass.
    public let edges: [ResolvedEdge]
    public let environment: DiagramRenderEnvironment

    public init(contentBounds: CGRect, topLevel: [ResolvedElement],
                edges: [ResolvedEdge], environment: DiagramRenderEnvironment) {
        self.contentBounds = contentBounds
        self.topLevel = topLevel
        self.edges = edges
        self.environment = environment
    }
}

public struct ResolvedElement: Sendable {
    public let uuid: String
    public let code: String
    public let name: String
    /// Diagram-space frame (transforms already composed).
    public let frame: CGRect
    public let elementZ: Double
    public let kind: ResolvedElementKind
    public let children: [ResolvedElement]
    /// This element's composed diagram-space center — the same value the
    /// resolver positioned the frame around. Hosts invert view hits with it
    /// instead of re-walking the tree.
    public let accumulatedCenter: CGPoint
    /// This element's OWN composed scale (parentScale × node.scale). The
    /// drag-delta divisor is the PARENT's accumulated scale — use
    /// `DiagramDrag.moveMutation`, which divides correctly, rather than
    /// dividing by this value directly.
    public let accumulatedScale: Double

    public init(uuid: String, code: String, name: String, frame: CGRect,
                elementZ: Double, kind: ResolvedElementKind, children: [ResolvedElement],
                accumulatedCenter: CGPoint = .zero, accumulatedScale: Double = 1) {
        self.uuid = uuid
        self.code = code
        self.name = name
        self.frame = frame
        self.elementZ = elementZ
        self.kind = kind
        self.children = children
        self.accumulatedCenter = accumulatedCenter
        self.accumulatedScale = accumulatedScale
    }

    /// Value-semantics rebuilds used by the deferred pass, which has to
    /// patch geometry into a tree phase 1 already built.
    func replacingChildren(_ children: [ResolvedElement]) -> ResolvedElement {
        ResolvedElement(uuid: uuid, code: code, name: name, frame: frame,
                        elementZ: elementZ, kind: kind, children: children,
                        accumulatedCenter: accumulatedCenter,
                        accumulatedScale: accumulatedScale)
    }

    func replacing(kind: ResolvedElementKind, frame: CGRect,
                   children: [ResolvedElement]) -> ResolvedElement {
        ResolvedElement(uuid: uuid, code: code, name: name, frame: frame,
                        elementZ: elementZ, kind: kind, children: children,
                        accumulatedCenter: accumulatedCenter,
                        accumulatedScale: accumulatedScale)
    }
}

extension ResolvedElement {
    /// Diagram-space y of one drawn property row's center on this entity
    /// card — the FK-exit formula. `resolveEdges` and the host's search
    /// field-jump both call this, so the two can never disagree. Row order
    /// is own-properties-first, composed-base union appended.
    public func rowCenterY(_ rowIndex: Int, environment: DiagramRenderEnvironment) -> CGFloat {
        DiagramResolver.rowCenterY(frameMinY: frame.minY, scale: accumulatedScale,
                                   rowIndex: rowIndex, environment: environment)
    }
}

extension ResolvedDiagram {
    /// Swap ONLY the color scheme — an O(1) copy for live appearance flips.
    /// Valid because `DiagramResolver.resolve` never reads
    /// `environment.colorScheme` (geometry depends only on the card metrics);
    /// changing metrics or padding still requires a full resolve.
    public func reskinned(_ scheme: DiagramRenderEnvironment.ColorScheme) -> ResolvedDiagram {
        guard scheme != environment.colorScheme else { return self }
        let env = DiagramRenderEnvironment(
            colorScheme: scheme, displayScale: environment.displayScale,
            padding: environment.padding, cardWidth: environment.cardWidth,
            cardHeaderHeight: environment.cardHeaderHeight,
            cardRowHeight: environment.cardRowHeight)
        return ResolvedDiagram(contentBounds: contentBounds, topLevel: topLevel,
                               edges: edges, environment: env)
    }
}

/// The exhaustive render-kind switch — the prompt's critical design pattern,
/// compiler-enforced: a new element type (or the ghost state) cannot ship
/// without every render site handling it.
public enum ResolvedElementKind: Sendable {
    case layer(LayerStyle)
    case stroke(ResolvedStroke)
    case shape(ResolvedShape)
    case text(ResolvedText)
    case connector(ResolvedConnector)
    case umlNode(ResolvedUmlNode)
    case scopeCard(ResolvedScopeCard)
    case entityCard(EntityCardModel)
    /// The LEGAL dangling-binding state: a dope_scope code matching no scope,
    /// or an entity code matching nothing in the resolved scope. A ghost,
    /// never an error.
    case absentScope(code: String)
    case absentEntity(code: String)
}

/// A laid-out markdown text box. `width`/`height` come from the subtype row
/// scaled by the accumulated tree scale — never from a vertex extent, so the
/// wrapping width is known before layout rather than derived from it.
public struct ResolvedText: Hashable, Sendable {
    public let markdown: String
    public let fontSize: Double
    public let textColor: String
    public let backgroundColor: String?

    public init(markdown: String, fontSize: Double,
                textColor: String, backgroundColor: String?) {
        self.markdown = markdown
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

/// A resolved connector.
///
/// `target` carries the ghost doctrine one level down: a connector whose
/// target was deleted (the column is ON DELETE SET NULL) or whose target
/// never resolved is `.absent` and simply does not draw, rather than
/// failing the diagram. Nothing about a missing endpoint is an error.
public struct ResolvedConnector: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case resolved(CGRect)
        case absent
    }

    public let target: Target
    public let strokeColor: String
    public let lineWidth: Double
    public let lineStyle: DiagramConnectorLineStyle
    public let headKind: DiagramConnectorHead
    public let routingKind: DiagramConnectorRouting
    public let tailKind: DiagramConnectorHead
    public let label: String

    public init(target: Target, strokeColor: String, lineWidth: Double,
                lineStyle: DiagramConnectorLineStyle,
                headKind: DiagramConnectorHead,
                routingKind: DiagramConnectorRouting = .orthogonalStep,
                tailKind: DiagramConnectorHead = .none,
                label: String) {
        self.target = target
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.lineStyle = lineStyle
        self.headKind = headKind
        self.routingKind = routingKind
        self.tailKind = tailKind
        self.label = label
    }
}

/// A resolved UML node: explicit frame (never text-measured), a kind that
/// picks the chrome, and the markdown interior. Optional chrome is
/// nil-means-theme-default so unstyled nodes stay legible in both schemes.
public struct ResolvedUmlNode: Hashable, Sendable {
    public let nodeKind: DiagramNodeKind
    public let markdown: String
    public let fontSize: Double
    public let textColor: String?
    public let strokeColor: String?
    public let lineWidth: Double
    public let fillColor: String?

    public init(nodeKind: DiagramNodeKind, markdown: String, fontSize: Double,
                textColor: String?, strokeColor: String?, lineWidth: Double,
                fillColor: String?) {
        self.nodeKind = nodeKind
        self.markdown = markdown
        self.fontSize = fontSize
        self.textColor = textColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.fillColor = fillColor
    }
}

public struct LayerStyle: Hashable, Sendable {
    public let opacity: Double
    public let visible: Bool
    public let locked: Bool

    public init(opacity: Double, visible: Bool, locked: Bool) {
        self.opacity = opacity
        self.visible = visible
        self.locked = locked
    }
}

public struct ResolvedStroke: Sendable {
    /// Diagram-space points (element-local vertices transformed).
    public let points: [CGPoint]
    public let color: String
    /// Scales with the accumulated transform.
    public let lineWidth: Double
    public let tool: DiagramStrokeTool
    /// The perfect-freehand outline polygon, derived at resolve time from
    /// the persisted centerline+pressure (renderAlgoVersion 2). Empty =
    /// degenerate stroke; the view falls back to the plain stroked line.
    public let outline: [CGPoint]

    public init(points: [CGPoint], color: String, lineWidth: Double,
                tool: DiagramStrokeTool, outline: [CGPoint] = []) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.tool = tool
        self.outline = outline
    }
}

public struct ResolvedShape: Sendable {
    public let kind: DiagramShapeKind
    public let points: [CGPoint]
    public let strokeColor: String
    public let lineWidth: Double
    public let fillColor: String?
    public let cornerRadius: Double?

    public init(kind: DiagramShapeKind, points: [CGPoint], strokeColor: String,
                lineWidth: Double, fillColor: String?, cornerRadius: Double?) {
        self.kind = kind
        self.points = points
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
    }
}

public struct ResolvedScopeCard: Sendable {
    public let dopeScopeCode: String
    public let scopeName: String
    /// "prompt" | "session_base" — which ladder rung won.
    public let resolvedVia: String

    public init(dopeScopeCode: String, scopeName: String, resolvedVia: String) {
        self.dopeScopeCode = dopeScopeCode
        self.scopeName = scopeName
        self.resolvedVia = resolvedVia
    }
}

/// dbdiagram-style card contents — 100% derived state (authored geometry is
/// the only thing persisted): header colored by the DOMAIN code's stable
/// hue, entity name + code, property rows name-left/type-right, badges.
public struct EntityCardModel: Sendable {
    public struct PropertyRow: Hashable, Sendable {
        public let name: String
        public let typeLabel: String
        /// "NN" (not nullable), "UQ" (unique), "AI" (auto-increment),
        /// "FK" (relationship), "B" (materialized from a composed base).
        public let badges: [String]

        public init(name: String, typeLabel: String, badges: [String]) {
            self.name = name
            self.typeLabel = typeLabel
            self.badges = badges
        }
    }

    /// 2-segment domain.entity binding code.
    public let entityCode: String
    public let entityName: String
    public let domainCode: String
    /// The entity's OWN code — i.e. the table name, the second segment of
    /// `entityCode`. Cards render this, never the 2-segment binding path:
    /// the domain is already carried by the header hue and the enclosing
    /// scope card, so repeating it in the header is noise.
    public var tableName: String {
        entityCode.split(separator: ".").last.map(String.init) ?? entityCode
    }
    /// Stable FNV-1a hue in [0, 1).
    public let headerHue: Double
    public let rows: [PropertyRow]

    public init(entityCode: String, entityName: String, domainCode: String,
                headerHue: Double, rows: [PropertyRow]) {
        self.entityCode = entityCode
        self.entityName = entityName
        self.domainCode = domainCode
        self.headerHue = headerHue
        self.rows = rows
    }
}

/// What produced an edge.
///
/// Both producers feed the SAME router call, so an edge has to say which it
/// came from — a derived FK arrow and a hand-drawn connector look different
/// and mean different things, but they route identically and must not be
/// two parallel routing systems.
public enum ResolvedEdgeOrigin: Sendable, Equatable {
    /// Derived from a dope relationship property. Nothing persisted it.
    case dopeForeignKey
    /// A persisted `connector` element, carrying its own styling.
    case connector(elementUuid: String, style: ResolvedConnector)
}

public struct ResolvedEdge: Sendable {
    /// Diagram-space anchor points on the two card borders. When `routed`,
    /// these are the routed polyline's real endpoints (`points.first/.last`).
    public let from: CGPoint
    public let to: CGPoint
    public let fromElementUuid: String
    public let toElementUuid: String
    /// `domain.entity.property` of the relationship property. For a
    /// connector this is its element code — the edge's human name either way.
    public let propertyRef: String
    /// Diagram-space orthogonal polyline, >= 2 points — `[from, to]` when
    /// routing declined (`routed == false`) and the view keeps the legacy
    /// cubic. Derived state: never persisted, never on the wire.
    public let points: [CGPoint]
    public let routed: Bool
    public let origin: ResolvedEdgeOrigin

    public init(from: CGPoint, to: CGPoint, fromElementUuid: String,
                toElementUuid: String, propertyRef: String,
                points: [CGPoint]? = nil, routed: Bool = false,
                origin: ResolvedEdgeOrigin = .dopeForeignKey) {
        self.from = from
        self.to = to
        self.fromElementUuid = fromElementUuid
        self.toElementUuid = toElementUuid
        self.propertyRef = propertyRef
        self.points = points ?? [from, to]
        self.routed = routed
        self.origin = origin
    }
}

public enum DiagramResolver {

    /// The one entry point. Semantics frozen here:
    ///  - `center_x/y` are PARENT-space; vertices are element-local; `scale`
    ///    composes multiplicatively; stroke width scales with the
    ///    accumulated transform.
    ///  - `element_z` orders SIBLINGS only, tie-broken by code; global paint
    ///    order is depth-first (a child never interleaves between another
    ///    parent's children — deliberate).
    ///  - Ghost injection happens here, once: an unresolved scope code makes
    ///    the scope card `.absentScope` and its entity children
    ///    `.absentEntity`; a resolved scope with a code-matches-nothing
    ///    entity makes just that card `.absentEntity`.
    public static func resolve(
        _ tree: DiagramTree,
        dope: DiagramDopeContext,
        environment: DiagramRenderEnvironment = DiagramRenderEnvironment()
    ) -> ResolvedDiagram {
        var entityFrames: [String: (frame: CGRect, entityCode: String,
                                    scopeCode: String, scale: Double)] = [:]
        var obstacles: [DiagramEdgeRouter.Obstacle] = []

        // PHASE 1 — place every immediate element, recording EVERY frame by
        // uuid (not just entity cards) and collecting the deferred ones.
        var pass = ResolvePass()
        let sortedTop = tree.elements.sorted(by: siblingOrder)
        let placed = sortedTop.map { node in
            resolveElement(node, parentCenter: .zero, parentScale: 1,
                           scope: scopeEntry(for: node, dope: dope),
                           environment: environment, entityFrames: &entityFrames,
                           obstacles: &obstacles, pass: &pass)
        }

        // PHASE 2 — the deferred pass. Every immediate element now has a
        // frame, so a connector can finally be told where its endpoints are.
        //
        // Both producers emit into ONE router call in a FIXED order (FK
        // first, then connectors, each internally sorted), because
        // DiagramEdgeRouter routes against a shared obstacle graph and index
        // i in is index i out. Two separate calls would route each set
        // blind to the other's corridors, and screenshot determinism would
        // depend on dictionary iteration order.
        let fkSeeds = foreignKeyEdgeSeeds(dope: dope, entityFrames: entityFrames,
                                          environment: environment)
        let connectorSeeds = connectorEdgeSeeds(pass: pass)
        let seeds = fkSeeds + connectorSeeds
        let routes = DiagramEdgeRouter.route(edges: seeds.map(\.request),
                                             obstacles: obstacles,
                                             padding: edgeRoutingPadding)
        let edges = zip(seeds, routes).map { seed, route in
            if route.routed, route.points.count >= 2 {
                return ResolvedEdge(
                    from: route.points[0], to: route.points[route.points.count - 1],
                    fromElementUuid: seed.fromElementUuid,
                    toElementUuid: seed.toElementUuid,
                    propertyRef: seed.propertyRef,
                    points: route.points, routed: true, origin: seed.origin)
            }
            return ResolvedEdge(
                from: seed.fallbackFrom, to: seed.fallbackTo,
                fromElementUuid: seed.fromElementUuid,
                toElementUuid: seed.toElementUuid,
                propertyRef: seed.propertyRef, origin: seed.origin)
        }

        // Patch the placeholder connectors with their resolved targets, so
        // hit-testing and bounds see real geometry rather than the phase-1
        // zero-size stand-in.
        let topLevel = placed.map { patchDeferred($0, pass: pass) }

        var bounds = CGRect.null
        func union(_ element: ResolvedElement) {
            bounds = bounds.union(element.frame)
            for child in element.children { union(child) }
        }
        for element in topLevel { union(element) }
        for edge in edges {
            // Every routed point, not just the endpoints — detours around
            // perimeter cards must never clip out of the screenshot viewport.
            for point in edge.points {
                bounds = bounds.union(CGRect(origin: point, size: .zero))
            }
        }
        if bounds.isNull { bounds = CGRect(x: 0, y: 0, width: 320, height: 200) }

        return ResolvedDiagram(contentBounds: bounds, topLevel: topLevel,
                               edges: edges, environment: environment)
    }

    // MARK: - Internals

    private static func siblingOrder(_ a: DiagramElementNode, _ b: DiagramElementNode) -> Bool {
        if a.base.elementZ != b.base.elementZ { return a.base.elementZ < b.base.elementZ }
        return a.base.code < b.base.code
    }

    private static func scopeEntry(
        for node: DiagramElementNode, dope: DiagramDopeContext
    ) -> DiagramDopeContext.Entry? {
        if case .dopeScopePersistenceLayer(let payload) = node.payload {
            return dope.entries[payload.dopeScopeCode]
        }
        return nil
    }

    private static func resolveElement(
        _ node: DiagramElementNode, parentCenter: CGPoint, parentScale: Double,
        parentUuid: String? = nil,
        scope: DiagramDopeContext.Entry?, environment: DiagramRenderEnvironment,
        entityFrames: inout [String: (frame: CGRect, entityCode: String,
                                      scopeCode: String, scale: Double)],
        obstacles: inout [DiagramEdgeRouter.Obstacle],
        pass: inout ResolvePass
    ) -> ResolvedElement {
        let scale = parentScale * node.base.scale
        let center = CGPoint(x: parentCenter.x + node.base.centerX * parentScale,
                             y: parentCenter.y + node.base.centerY * parentScale)

        // Children first — container frames derive from child extents.
        let sortedChildren = node.children.sorted(by: siblingOrder)
        var children: [ResolvedElement] = []

        let kind: ResolvedElementKind
        var frame: CGRect

        switch node.payload {
        case .drawingLayer(let payload):
            children = sortedChildren.map {
                resolveElement($0, parentCenter: center, parentScale: scale,
                               parentUuid: node.identity.uuid,
                               scope: nil, environment: environment,
                               entityFrames: &entityFrames, obstacles: &obstacles,
                               pass: &pass)
            }
            kind = .layer(LayerStyle(opacity: payload.opacity, visible: payload.visible,
                                     locked: payload.locked))
            frame = children.reduce(CGRect.null) { $0.union($1.frame) }
            if frame.isNull {
                frame = CGRect(x: center.x - 100 * scale, y: center.y - 60 * scale,
                               width: 200 * scale, height: 120 * scale)
            }

        case .drawingStroke(let payload):
            let points = payload.vertices.map {
                CGPoint(x: center.x + $0.x * scale, y: center.y + $0.y * scale)
            }
            // Pressure-aware outline for the drawing tools; the highlighter
            // keeps its flat translucent band (an outline would read as
            // marker). Derivation only — nothing is persisted.
            let outline = payload.tool == .highlighter ? [] : StrokeOutliner.outline(
                points: points,
                pressures: payload.vertices.map(\.pressure),
                options: StrokeOutliner.Options(size: payload.strokeWidth * scale * 2))
            kind = .stroke(ResolvedStroke(points: points, color: payload.strokeColor,
                                          lineWidth: payload.strokeWidth * scale,
                                          tool: payload.tool, outline: outline))
            frame = points.isEmpty
                ? CGRect(origin: center, size: .zero)
                : points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }.insetBy(dx: -payload.strokeWidth * scale, dy: -payload.strokeWidth * scale)

        case .drawingShape(let payload):
            let points = payload.vertices.map {
                CGPoint(x: center.x + $0.x * scale, y: center.y + $0.y * scale)
            }
            kind = .shape(ResolvedShape(kind: payload.shapeKind, points: points,
                                        strokeColor: payload.strokeColor,
                                        lineWidth: payload.strokeWidth * scale,
                                        fillColor: payload.fillColor,
                                        cornerRadius: payload.cornerRadius.map { $0 * scale }))
            frame = points.isEmpty
                ? CGRect(x: center.x - 40 * scale, y: center.y - 40 * scale,
                         width: 80 * scale, height: 80 * scale)
                : points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }.insetBy(dx: -payload.strokeWidth * scale, dy: -payload.strokeWidth * scale)

        case .drawingText(let payload):
            let width = payload.width * scale
            let height = payload.height * scale
            frame = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                           width: width, height: height)
            kind = .text(ResolvedText(markdown: payload.markdown,
                                      fontSize: payload.fontSize * scale,
                                      textColor: payload.textColor,
                                      backgroundColor: payload.backgroundColor))

        case .connector(let payload):
            // DEFERRED. A connector's geometry is a function of its target's
            // frame, which does not exist yet during this walk — that is the
            // entire reason the resolve is two-phase. Phase 1 records what
            // phase 2 will need and leaves a placeholder; `patchDeferred`
            // fills in the real frame once every immediate element is
            // placed. A placeholder that never gets patched is a ghost, and
            // a ghost draws nothing.
            pass.deferred.append(ResolvePass.Deferred(
                uuid: node.identity.uuid, code: node.base.code,
                parentUuid: parentUuid, payload: payload, scale: scale))
            frame = CGRect(origin: center, size: .zero)
            kind = .connector(ResolvedConnector(
                target: .absent, strokeColor: payload.strokeColor,
                lineWidth: payload.strokeWidth * scale,
                lineStyle: payload.lineStyle, headKind: payload.headKind,
                routingKind: payload.routingKind, tailKind: payload.tailKind,
                label: payload.label))

        case .umlNode(let payload):
            // Connectors are children of the element they connect FROM, so
            // a node walks its children like an entity card does — and like
            // the card, its frame is its OWN explicit size, never a child
            // extent (a connector must not inflate the node it hangs off).
            children = sortedChildren.map {
                resolveElement($0, parentCenter: center, parentScale: scale,
                               parentUuid: node.identity.uuid,
                               scope: scope, environment: environment,
                               entityFrames: &entityFrames, obstacles: &obstacles,
                               pass: &pass)
            }
            let width = payload.width * scale
            let height = payload.height * scale
            frame = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                           width: width, height: height)
            kind = .umlNode(ResolvedUmlNode(
                nodeKind: payload.nodeKind, markdown: payload.markdown,
                fontSize: (payload.fontSize ?? 13) * scale,
                textColor: payload.textColor,
                strokeColor: payload.strokeColor,
                lineWidth: (payload.strokeWidth ?? 2) * scale,
                fillColor: payload.fillColor))

        case .dopeScopePersistenceLayer(let payload):
            children = sortedChildren.map {
                resolveElement($0, parentCenter: center, parentScale: scale,
                               parentUuid: node.identity.uuid,
                               scope: scope, environment: environment,
                               entityFrames: &entityFrames, obstacles: &obstacles,
                               pass: &pass)
            }
            if let scope {
                kind = .scopeCard(ResolvedScopeCard(
                    dopeScopeCode: payload.dopeScopeCode,
                    scopeName: scope.tree.body.name,
                    resolvedVia: scope.resolvedVia))
            } else {
                kind = .absentScope(code: payload.dopeScopeCode)
            }
            frame = children.reduce(CGRect.null) { $0.union($1.frame) }
            frame = frame.isNull
                ? CGRect(x: center.x - 140 * scale, y: center.y - 90 * scale,
                         width: 280 * scale, height: 180 * scale)
                : frame.insetBy(dx: -24 * scale, dy: -32 * scale)

        case .dopeEntity(let payload):
            // Entity cards had no children until connectors existed, and a
            // connector is BY DEFINITION a child of the entity it connects
            // from — so this arm has to walk them. The card's own frame is
            // still card metrics, never a child extent: a connector must
            // not inflate the card it hangs off.
            children = sortedChildren.map {
                resolveElement($0, parentCenter: center, parentScale: scale,
                               parentUuid: node.identity.uuid,
                               scope: scope, environment: environment,
                               entityFrames: &entityFrames, obstacles: &obstacles,
                               pass: &pass)
            }
            if let scope, let model = entityCard(payload.entityCode, in: scope.tree) {
                let width = environment.cardWidth * scale
                let height = environment.cardHeight(rowCount: model.rows.count) * scale
                frame = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                               width: width, height: height)
                kind = .entityCard(model)
                entityFrames[node.identity.uuid] =
                    (frame, payload.entityCode, scope.tree.body.code, scale)
                obstacles.append(DiagramEdgeRouter.Obstacle(frame: frame, scale: scale))
            } else {
                let width = environment.cardWidth * scale
                let height = environment.cardHeight(rowCount: 1) * scale
                frame = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                               width: width, height: height)
                kind = .absentEntity(code: payload.entityCode)
                // Ghost cards are obstacles too — edges route around them,
                // they just never produce edges themselves.
                obstacles.append(DiagramEdgeRouter.Obstacle(frame: frame, scale: scale))
            }
        }

        // EVERY element's frame goes in the index, not just entity cards —
        // that is what lets phase 2 resolve a connector against any element.
        let type = node.payload.elementType
        var nodeKind: DiagramNodeKind?
        if case .umlNode(let payload) = node.payload { nodeKind = payload.nodeKind }
        pass.frames[node.identity.uuid] = ResolvePass.Frame(
            frame: frame, type: type, parentUuid: parentUuid, scale: scale,
            nodeKind: nodeKind)

        // Obstacle participation is now DATA on the registry rather than a
        // hardcoded branch: structural content (entity cards, shapes, text
        // boxes) blocks routing; ink, layers and connectors do not. The
        // dopeEntity arms above already appended, so this covers the rest
        // without double-counting them.
        if DiagramElementTypeSpec.spec(for: type).participatesInRouting,
           type != .dopeEntity, !frame.isNull, frame.width > 0, frame.height > 0 {
            obstacles.append(DiagramEdgeRouter.Obstacle(frame: frame, scale: scale))
        }

        return ResolvedElement(uuid: node.identity.uuid, code: node.base.code,
                               name: node.base.name, frame: frame,
                               elementZ: node.base.elementZ, kind: kind,
                               children: children,
                               accumulatedCenter: center, accumulatedScale: scale)
    }

    /// Card contents from the hydrated dope tree: the entity's own
    /// properties plus the composed-base union (walked through the
    /// baseComposableRef chain — bases are never replicated in the db, so
    /// render time is where the union happens).
    static func entityCard(_ entityCode: String, in tree: DopeScopeTree) -> EntityCardModel? {
        let segments = entityCode.split(separator: ".").map(String.init)
        guard segments.count == 2 else { return nil }
        let (domainCode, code) = (segments[0], segments[1])
        guard let domain = tree.domains.first(where: { $0.body.code == domainCode }),
              let entity = domain.entities.first(where: { $0.body.code == code })
        else { return nil }

        func lookupEntity(_ ref: String) -> DopeEntityNode? {
            let parts = ref.split(separator: ".").map(String.init)
            guard parts.count == 2,
                  let d = tree.domains.first(where: { $0.body.code == parts[0] })
            else { return nil }
            return d.entities.first(where: { $0.body.code == parts[1] })
        }

        func rows(for node: DopeEntityNode, fromBase: Bool) -> [EntityCardModel.PropertyRow] {
            node.properties.map { property in
                var badges: [String] = []
                if !property.body.nullable { badges.append("NN") }
                if property.body.isUnique { badges.append("UQ") }
                if property.body.autoIncrement == true { badges.append("AI") }
                if property.body.relationshipTargetRef != nil { badges.append("FK") }
                if fromBase || property.body.baseOriginRef != nil { badges.append("B") }
                let typeLabel: String
                if let enumRef = property.body.enumRef {
                    typeLabel = "enum(\(enumRef.split(separator: ".").last.map(String.init) ?? enumRef))"
                } else if let related = property.body.relationshipTargetRef {
                    typeLabel = "→ \(related)"
                } else {
                    typeLabel = property.body.dataType
                }
                // `name` is the property's OWN code — the snake_case column
                // name exactly as modeled, never the dot-path.
                return EntityCardModel.PropertyRow(
                    name: property.body.code, typeLabel: typeLabel, badges: badges)
            }
        }

        var allRows = rows(for: entity, fromBase: false)
        // Composed-base union: chain-walk with a visited set (cycles are
        // refused on write; the set is defensive).
        var seen: Set<String> = [entityCode]
        var baseRef = entity.body.baseComposableRef
        while let ref = baseRef, seen.insert(ref).inserted, let base = lookupEntity(ref) {
            allRows.append(contentsOf: rows(for: base, fromBase: true))
            baseRef = base.body.baseComposableRef
        }

        return EntityCardModel(
            entityCode: entityCode, entityName: entity.body.name,
            domainCode: domainCode,
            headerHue: DiagramPalette.domainHue(domainCode),
            rows: allRows)
    }

    // MARK: - The two-phase resolve

    /// Phase-1 state: what phase 2 needs and phase 1 is the only thing that
    /// can know.
    ///
    /// `frames` holds EVERY element, keyed by uuid. The older `entityFrames`
    /// dictionary is kept alongside it rather than replaced: it carries dope
    /// metadata (entityCode, scopeCode) that only entity cards have, and the
    /// FK producer is written against exactly that. Widening it would have
    /// meant making those fields optional on every element in the diagram to
    /// serve one producer.
    struct ResolvePass {
        struct Frame {
            let frame: CGRect
            let type: DiagramElementType
            let parentUuid: String?
            let scale: Double
            var nodeKind: DiagramNodeKind?

            /// The frame ANCHORS attach to. A triangle's side midpoints are
            /// empty space (the outline slopes inward), so its anchor frame
            /// insets horizontally to where the outline actually is at
            /// mid-height. Obstacles keep the FULL frame — edges must still
            /// route around the base.
            var anchorFrame: CGRect {
                guard nodeKind == .triangle else { return frame }
                return frame.insetBy(dx: frame.width * 0.24, dy: 0)
            }
        }
        /// Every immediate element, by uuid.
        var frames: [String: Frame] = [:]
        /// Deferred elements awaiting phase 2, in tree order.
        var deferred: [Deferred] = []
        /// Filled by phase 2: connector uuid -> its resolved geometry.
        var resolvedConnectors: [String: (connector: ResolvedConnector, frame: CGRect)] = [:]

        struct Deferred {
            let uuid: String
            let code: String
            let parentUuid: String?
            let payload: ConnectorPayload
            let scale: Double
        }
    }

    /// Connector seeds, computed against the completed frame index.
    ///
    /// A connector's endpoints are its PARENT's frame and its TARGET's
    /// frame — it is rendered as a child of the thing it connects from, so
    /// the parent IS the source anchor. Anything unresolvable (no parent, no
    /// target, a target that was deleted) is a ghost: it emits no seed and
    /// draws nothing, exactly like a dangling dope binding.
    private static func connectorEdgeSeeds(pass: ResolvePass) -> [EdgeSeed] {
        var seeds: [EdgeSeed] = []
        // Sorted by uuid so routing order — and therefore the rendered
        // geometry — never depends on tree traversal incidentals.
        for deferred in pass.deferred.sorted(by: { $0.uuid < $1.uuid }) {
            guard let parentUuid = deferred.parentUuid,
                  let source = pass.frames[parentUuid],
                  let targetUuid = deferred.payload.targetElementUuid,
                  let target = pass.frames[targetUuid]
            else { continue }
            let (from, to) = anchorPoints(source.anchorFrame, target.anchorFrame)
            seeds.append(EdgeSeed(
                request: DiagramEdgeRouter.EdgeRequest(
                    fromFrame: source.anchorFrame, toFrame: target.anchorFrame,
                    sourceRowY: source.anchorFrame.midY,
                    propertyRef: deferred.code,
                    fromElementUuid: parentUuid),
                fallbackFrom: from, fallbackTo: to,
                fromElementUuid: parentUuid, toElementUuid: targetUuid,
                propertyRef: deferred.code,
                origin: .connector(
                    elementUuid: deferred.uuid,
                    style: ResolvedConnector(
                        target: .resolved(target.frame),
                        strokeColor: deferred.payload.strokeColor,
                        lineWidth: deferred.payload.strokeWidth * deferred.scale,
                        lineStyle: deferred.payload.lineStyle,
                        headKind: deferred.payload.headKind,
                        routingKind: deferred.payload.routingKind,
                        tailKind: deferred.payload.tailKind,
                        label: deferred.payload.label))))
        }
        return seeds
    }

    /// Replace phase-1's placeholder connector kinds with resolved geometry.
    ///
    /// A connector's own frame becomes the union of its endpoints, so the
    /// diagram's content bounds include it and a screenshot cannot clip a
    /// connector that runs outside every card.
    private static func patchDeferred(
        _ element: ResolvedElement, pass: ResolvePass
    ) -> ResolvedElement {
        let children = element.children.map { patchDeferred($0, pass: pass) }
        guard case .connector(let placeholder) = element.kind else {
            return element.replacingChildren(children)
        }
        guard let deferred = pass.deferred.first(where: { $0.uuid == element.uuid }),
              let parentUuid = deferred.parentUuid,
              let source = pass.frames[parentUuid],
              let targetUuid = deferred.payload.targetElementUuid,
              let target = pass.frames[targetUuid]
        else {
            // Ghost: unresolvable endpoint. Legal, renders nothing.
            return element.replacingChildren(children)
        }
        return element.replacing(
            kind: .connector(ResolvedConnector(
                target: .resolved(target.frame),
                strokeColor: placeholder.strokeColor,
                lineWidth: placeholder.lineWidth,
                lineStyle: placeholder.lineStyle,
                headKind: placeholder.headKind,
                routingKind: placeholder.routingKind,
                tailKind: placeholder.tailKind,
                label: placeholder.label)),
            frame: source.frame.union(target.frame),
            children: children)
    }

    /// One edge to route, from either producer.
    struct EdgeSeed {
        let request: DiagramEdgeRouter.EdgeRequest
        let fallbackFrom: CGPoint
        let fallbackTo: CGPoint
        let fromElementUuid: String
        let toElementUuid: String
        let propertyRef: String
        let origin: ResolvedEdgeOrigin
    }

    /// The FK edge pass: for every relationship property of every rendered
    /// entity card, if the target property's owning entity also has a card
    /// under the SAME scope element family, draw an edge between the two
    /// card borders.
    /// Base routing padding in points, scaled per-obstacle by accumulated
    /// scale. Coupled to the frozen layout generator's corridors
    /// (diagram_from_dope.py: 50pt gutters, 48pt row gaps) — must stay < 24
    /// or the vertical row-gap corridors close entirely. Deliberately NOT a
    /// DiagramRenderEnvironment knob: it is routing policy, not a render
    /// setting. Internal (not private) so the corridor-arithmetic fixture
    /// pins THIS value against the generator constants — changing it without
    /// updating the fixture breaks loudly.
    static let edgeRoutingPadding: Double = 12

    private static func foreignKeyEdgeSeeds(
        dope: DiagramDopeContext,
        entityFrames: [String: (frame: CGRect, entityCode: String,
                                scopeCode: String, scale: Double)],
        environment: DiagramRenderEnvironment
    ) -> [EdgeSeed] {
        // entityCode+scopeCode → (uuid, frame). Built from a SORTED walk with
        // first-wins so duplicate cards binding the same entity always pick
        // the same (lowest-uuid) target — screenshot determinism is a
        // correctness requirement, and dictionary iteration order is not.
        var cardByEntity: [String: (uuid: String, frame: CGRect)] = [:]
        for (uuid, info) in entityFrames.sorted(by: { $0.key < $1.key }) {
            let key = "\(info.scopeCode)|\(info.entityCode)"
            if cardByEntity[key] == nil {
                cardByEntity[key] = (uuid, info.frame)
            }
        }

        // Emission pass: one spec + one legacy fallback pair per FK, in
        // sorted-by-uuid order (which is also the routing order).
        var seeds: [EdgeSeed] = []
        for (uuid, info) in entityFrames.sorted(by: { $0.key < $1.key }) {
            guard let scope = dope.entries[info.scopeCode] else { continue }
            let segments = info.entityCode.split(separator: ".").map(String.init)
            guard segments.count == 2,
                  let domain = scope.tree.domains.first(where: { $0.body.code == segments[0] }),
                  let entity = domain.entities.first(where: { $0.body.code == segments[1] })
            else { continue }
            for (rowIndex, property) in entity.properties.enumerated() {
                guard let ref = property.body.relationshipTargetRef else { continue }
                let parts = ref.split(separator: ".").map(String.init)
                guard parts.count == 3 else { continue }
                let targetEntityCode = "\(parts[0]).\(parts[1])"
                guard let target = cardByEntity["\(info.scopeCode)|\(targetEntityCode)"],
                      target.uuid != uuid
                else { continue }
                // The edge leaves at the FK property ROW's y. rowIndex maps
                // 1:1 to drawn rows: own properties render first, the
                // composed-base union only appends after them.
                let rowY = rowCenterY(frameMinY: info.frame.minY, scale: info.scale,
                                      rowIndex: rowIndex, environment: environment)
                let (from, to) = anchorPoints(info.frame, target.frame)
                seeds.append(EdgeSeed(
                    request: DiagramEdgeRouter.EdgeRequest(
                        fromFrame: info.frame, toFrame: target.frame,
                        sourceRowY: rowY,
                        propertyRef: "\(info.entityCode).\(property.body.code)",
                        fromElementUuid: uuid),
                    fallbackFrom: from, fallbackTo: to,
                    fromElementUuid: uuid, toElementUuid: target.uuid,
                    propertyRef: "\(info.entityCode).\(property.body.code)",
                    origin: .dopeForeignKey))
            }
        }
        // Routing is the CALLER's — one shared-graph call for every producer,
        // so FK edges and connectors steer around the same obstacles.
        return seeds
    }

    /// The single home of the FK-row y formula — `resolveEdges` anchors and
    /// `ResolvedElement.rowCenterY` (the host's search field-jump) both call
    /// this, so the two can never disagree.
    static func rowCenterY(frameMinY: CGFloat, scale: Double, rowIndex: Int,
                           environment: DiagramRenderEnvironment) -> CGFloat {
        frameMinY + (environment.cardHeaderHeight
            + (Double(rowIndex) + 0.5) * environment.cardRowHeight) * scale
    }

    /// Side-midpoint anchors: leave from the edge facing the target.
    private static func anchorPoints(_ a: CGRect, _ b: CGRect) -> (CGPoint, CGPoint) {
        if b.midX >= a.midX {
            return (CGPoint(x: a.maxX, y: a.midY), CGPoint(x: b.minX, y: b.midY))
        } else {
            return (CGPoint(x: a.minX, y: a.midY), CGPoint(x: b.maxX, y: b.midY))
        }
    }
}
