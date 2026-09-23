#if canImport(SwiftUI)
import SwiftUI

// The DIAGRAM component library. Every view consumes ResolvedDiagram values from
// DiagramResolver, so rendering needs no client, database or daemon; it is a
// hybrid of SwiftUI views for dope cards and Canvas paths for strokes and edges.
//
// COORDINATE CONTRACT: the resolver emits DIAGRAM-space geometry and the view
// layer adds one offset INSIDE each Canvas (context.translateBy) and on each
// .position, never as a .offset modifier — Canvas clips to its own bounds before
// a view offset applies, silently discarding negative-coordinate content.

/// Root view: draws a resolved diagram, offset so contentBounds' origin lands
/// at (padding, padding).
///
/// Only the two parent-level kinds appear at the top (the store's invariant);
/// the switch is exhaustive anyway — the compiler forces every render site to
/// handle every kind, ghosts included (the prompt's critical design pattern).
struct DiagramCanvasView: View {
    let resolved: ResolvedDiagram

    /// Creates a canvas view for a resolved diagram.
    ///
    /// - Parameter resolved: The resolved diagram to render.
    init(resolved: ResolvedDiagram) {
        self.resolved = resolved
    }

    /// Diagram-space → view-space translation.
    private var offset: CGSize {
        CGSize(
            width: resolved.environment.padding - resolved.contentBounds.minX,
            height: resolved.environment.padding - resolved.contentBounds.minY
        )
    }

    var totalSize: CGSize {
        CGSize(
            width: resolved.contentBounds.width + resolved.environment.padding * 2,
            height: resolved.contentBounds.height + resolved.environment.padding * 2
        )
    }

    var body: some View {
        // The screenshot wrapper is DiagramSceneView's first customer: the
        // background rides the underlay slot (UN-offset — it paints the whole
        // frame), so the rendered tree keeps the pre-split single ZStack with
        // the same children in the same order. Content-derived offset, fixed
        // frame, and the forced colorScheme override are screenshot framing
        // and live ONLY here — interactive hosts compose DiagramSceneView
        // directly with their own stable offset and live appearance.
        DiagramSceneView(resolved: resolved, offset: offset) {
            (resolved.environment.colorScheme == .dark
                ? Color(red: 0.11, green: 0.11, blue: 0.13)
                : Color(red: 0.97, green: 0.97, blue: 0.98))
        }
        .frame(width: totalSize.width, height: totalSize.height, alignment: .topLeading)
        .environment(\.colorScheme, resolved.environment.colorScheme == .dark ? .dark : .light)
    }
}

/// One resolved element + its children.
///
/// Exhaustive switch #2 (the resolver's kind construction is #1) — both
/// compiler-enforced over the same enum.
struct ResolvedElementView: View {
    let element: ResolvedElement
    let environment: DiagramRenderEnvironment
    let offset: CGSize

    /// Creates a view for a resolved element and its children.
    ///
    /// - Parameters:
    ///   - element: The resolved element to render.
    ///   - environment: The diagram rendering environment.
    ///   - offset: The offset in view space; defaults to zero.
    init(
        element: ResolvedElement,
        environment: DiagramRenderEnvironment,
        offset: CGSize = .zero
    ) {
        self.element = element
        self.environment = environment
        self.offset = offset
    }

    var body: some View {
        Group {
            switch element.kind {
            case .layer(let style):
                DrawingLayerView(
                    element: element,
                    style: style,
                    environment: environment,
                    offset: offset
                )
            case .stroke(let stroke):
                StrokeView(stroke: stroke, offset: offset)
            case .shape(let shape):
                ShapeView(shape: shape, offset: offset)
            case .text(let text):
                TextBoxView(element: element, text: text, offset: offset)
            case .connector(let connector):
                ConnectorView(element: element, connector: connector, offset: offset)
            case .umlNode(let node):
                UmlNodeView(element: element, node: node, offset: offset)
            case .scopeCard(let card):
                DopeScopeOutlineView(
                    element: element,
                    card: card,
                    environment: environment,
                    offset: offset
                )
            case .entityCard(let model):
                DopeEntityCardView(
                    element: element,
                    model: model,
                    environment: environment,
                    ghostCode: nil,
                    offset: offset
                )
            case .absentScope(let code):
                DopeScopeOutlineView(
                    element: element,
                    card: nil,
                    environment: environment,
                    ghostCode: code,
                    offset: offset
                )
            case .absentEntity(let code):
                DopeEntityCardView(
                    element: element,
                    model: nil,
                    environment: environment,
                    ghostCode: code,
                    offset: offset
                )
            }
        }
    }
}

/// An endless, totally transparent grouping surface: renders nothing itself
/// beyond its children (a faint outline when locked/invisible would lie in a
/// screenshot), honoring opacity/visibility.
struct DrawingLayerView: View {
    let element: ResolvedElement
    let style: LayerStyle
    let environment: DiagramRenderEnvironment
    let offset: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(element.children, id: \.uuid) { child in
                ResolvedElementView(
                    element: child,
                    environment: environment,
                    offset: offset
                )
            }
        }
        .opacity(style.visible ? style.opacity : 0)
    }
}

struct StrokeView: View {
    let stroke: ResolvedStroke
    let offset: CGSize

    var body: some View {
        Canvas { context, _ in
            guard stroke.points.count >= 2 else { return }
            // Translate INSIDE the canvas — see the coordinate contract.
            context.translateBy(x: offset.width, y: offset.height)
            var color = Color(hex: stroke.color)
            if stroke.tool == .highlighter { color = color.opacity(0.4) }
            // Pressure-aware outline when the resolver derived one
            // (renderAlgoVersion 2); plain centerline stroke otherwise.
            if stroke.outline.count >= 3 {
                var path = Path()
                path.move(to: stroke.outline[0])
                for point in stroke.outline.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            } else {
                var path = Path()
                path.move(to: stroke.points[0])
                for point in stroke.points.dropFirst() { path.addLine(to: point) }
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: stroke.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// A markdown text box at its explicit size.
///
/// v23: block-level markdown via the kit's own MarkdownBlocksView (the
/// renderer promoted from GMVibes — headings, lists, fenced code, tables),
/// exactly the addition the inline-only deferral anticipated. The wrapping
/// model is unchanged: explicit frame, top-leading, clipped.
struct TextBoxView: View {
    let element: ResolvedElement
    let text: ResolvedText
    let offset: CGSize

    var body: some View {
        MarkdownBlocksView(source: text.markdown, baseFontSize: text.fontSize)
            .foregroundStyle(Color(hex: text.textColor))
            .frame(
                width: element.frame.width,
                height: element.frame.height,
                alignment: .topLeading
            )
            .clipped()
            .background(text.backgroundColor.map { Color(hex: $0) })
            .position(
                x: element.frame.midX + offset.width,
                y: element.frame.midY + offset.height
            )
            .allowsHitTesting(false)
    }
}

/// A connector element renders NOTHING here, on purpose.
///
/// `DiagramEdgeCanvas` draws connectors as routed polylines, in the same pass and
/// against the same obstacle graph as FK edges; drawing the element too would
/// paint a second, straight, unrouted line over the routed one. The element still
/// exists in the tree so it can be selected, deleted and carry its own identity.
struct ConnectorView: View {
    let element: ResolvedElement
    let connector: ResolvedConnector
    let offset: CGSize

    var body: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
    }
}

struct ShapeView: View {
    let shape: ResolvedShape
    let offset: CGSize

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: offset.width, y: offset.height)
            let path = shapePath()
            if let fill = shape.fillColor {
                context.fill(path, with: .color(Color(hex: fill)))
            }
            context.stroke(
                path,
                with: .color(Color(hex: shape.strokeColor)),
                style: StrokeStyle(
                    lineWidth: shape.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .allowsHitTesting(false)
    }

    /// Constructs a path for the shape in the given bounds.
    ///
    /// - Returns: A path that draws the shape.
    private func shapePath() -> Path {
        var path = Path()
        let points = shape.points
        switch shape.kind {
        case .rectangle:
            guard points.count >= 2 else { return path }
            let rect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(
                    width: shape.cornerRadius ?? 0,
                    height: shape.cornerRadius ?? 0
                )
            )
        case .ellipse:
            guard points.count >= 2 else { return path }
            let rect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            path.addEllipse(in: rect)
        case .line:
            guard points.count >= 2 else { return path }
            path.move(to: points[0])
            path.addLine(to: points[1])
        case .arrow:
            guard points.count >= 2 else { return path }
            let from = points[0], to = points[1]
            path.move(to: from)
            path.addLine(to: to)
            let angle = atan2(to.y - from.y, to.x - from.x)
            let head: CGFloat = max(8, shape.lineWidth * 3)
            path.move(to: to)
            path.addLine(
                to: CGPoint(
                    x: to.x - head * cos(angle - 0.5),
                    y: to.y - head * sin(angle - 0.5)
                )
            )
            path.move(to: to)
            path.addLine(
                to: CGPoint(
                    x: to.x - head * cos(angle + 0.5),
                    y: to.y - head * sin(angle + 0.5)
                )
            )
        case .polygon:
            guard points.count >= 3 else { return path }
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}

/// A UML node: kind-picked chrome + the kit's block-markdown interior on a
/// transparent background — THE text surface for nodes.
///
/// Chrome colors are nil-means-theme-default so unstyled nodes are legible in
/// both schemes. Children (connectors) render nothing here — connector visuals
/// ride DiagramEdgeCanvas like every other edge.
struct UmlNodeView: View {
    let element: ResolvedElement
    let node: ResolvedUmlNode
    let offset: CGSize
    @Environment(\.diagramSelection) private var selection

    /// Creates a view for a UML node element.
    ///
    /// - Parameters:
    ///   - element: The resolved node element.
    ///   - node: The resolved UML node model.
    ///   - offset: The offset in view space; defaults to zero.
    init(
        element: ResolvedElement,
        node: ResolvedUmlNode,
        offset: CGSize = .zero
    ) {
        self.element = element
        self.node = node
        self.offset = offset
    }

    private var strokeColor: Color {
        node.strokeColor.map { Color(hex: $0) } ?? Color.primary.opacity(0.65)
    }

    private var fillColor: Color {
        node.fillColor.map { Color(hex: $0) } ?? Color.clear
    }

    /// Boxy chrome reads top-leading like a document; round and pointy
    /// chrome centers, or short labels sit in a corner the shape does not
    /// visually have.
    private var centersText: Bool {
        switch node.nodeKind {
        case .circle, .diamond, .triangle: return true
        case .roundedRect, .rhombus, .dbCylinder: return false
        }
    }

    /// Interior insets per kind — pointed chrome needs more breathing room
    /// than a rectangle before markdown collides with the outline.
    private var textInsets: EdgeInsets {
        let w = element.frame.width
        let h = element.frame.height
        switch node.nodeKind {
        case .roundedRect:
            return EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        case .dbCylinder:
            let cap = UmlNodeShape.cylinderCapHeight(for: element.frame)
            return EdgeInsets(top: cap * 2 + 4, leading: 10, bottom: 8, trailing: 10)
        case .triangle:
            return EdgeInsets(
                top: h * 0.45,
                leading: w * 0.22,
                bottom: 8,
                trailing: w * 0.22
            )
        case .rhombus:
            return EdgeInsets(top: 8, leading: w * 0.2, bottom: 8, trailing: w * 0.2)
        case .diamond:
            return EdgeInsets(
                top: h * 0.22,
                leading: w * 0.22,
                bottom: h * 0.22,
                trailing: w * 0.22
            )
        case .circle:
            return EdgeInsets(
                top: h * 0.16,
                leading: w * 0.16,
                bottom: h * 0.16,
                trailing: w * 0.16
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            UmlNodeShape(kind: node.nodeKind)
                .fill(fillColor)
            UmlNodeShape(kind: node.nodeKind)
                .stroke(strokeColor, lineWidth: node.lineWidth)
            if !node.markdown.isEmpty {
                MarkdownBlocksView(source: node.markdown, baseFontSize: node.fontSize)
                    .foregroundStyle(
                        node.textColor.map { Color(hex: $0) }
                            ?? Color.primary
                    )
                    .padding(textInsets)
                    .frame(
                        width: element.frame.width,
                        height: element.frame.height,
                        alignment: centersText ? .center : .topLeading
                    )
                    .clipped()
            }
        }
        .frame(width: element.frame.width, height: element.frame.height)
        .overlay {
            if selection.selectedElementUuid == element.uuid {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-3)
            }
        }
        .opacity(selection.dimmedElementUuids.contains(element.uuid) ? 0.35 : 1)
        .position(
            x: element.frame.midX + offset.width,
            y: element.frame.midY + offset.height
        )
        .allowsHitTesting(false)
    }
}

/// The UML chrome vocabulary as one Shape — pure geometry over the node's
/// rect, unit-testable via path(in:).
struct UmlNodeShape: Shape {
    let kind: DiagramNodeKind

    /// Creates a shape renderer for a diagram node.
    ///
    /// - Parameter kind: The diagram node kind.
    init(kind: DiagramNodeKind) {
        self.kind = kind
    }

    /// Returns the cylinder's cap half-height for a node.
    ///
    /// The cap is shallow enough that squat nodes keep a body, yet deep enough to
    /// read as a disk.
    ///
    /// - Parameter rect: The node bounds.
    /// - Returns: The half-height in points.
    static func cylinderCapHeight(for rect: CGRect) -> CGFloat {
        min(rect.height * 0.12, 18)
    }

    /// Constructs a path that draws the node shape in the given bounds.
    ///
    /// - Parameter rect: The bounds to fill.
    /// - Returns: A path for the node shape.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .roundedRect:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 10, height: 10))
        case .circle:
            path.addEllipse(in: rect)
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        case .rhombus:
            // The slanted parallelogram (UML input/output), lean = 18% width.
            let lean = rect.width * 0.18
            path.move(to: CGPoint(x: rect.minX + lean, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - lean, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        case .dbCylinder:
            let cap = Self.cylinderCapHeight(for: rect)
            let topRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: cap * 2
            )
            // ONE closed body subpath — sides, bottom bulge, and the top
            // ellipse's lower arc — so an explicit fill paints the whole
            // barrel, then the top disk as its own subpath. (v1 shipped a
            // stray zero-sweep addArc here that drew a chord across every
            // stroked cylinder, and disjoint open subpaths that filled as
            // wedges — the quad controls at ±cap*2 from the rim put the
            // curve APEX exactly one cap-height beyond it.)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + cap))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cap))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - cap),
                control: CGPoint(x: rect.midX, y: rect.maxY + cap)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cap))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + cap),
                control: CGPoint(x: rect.midX, y: rect.minY + cap * 3)
            )
            path.closeSubpath()
            path.addEllipse(in: topRect)
        }
        return path
    }
}

/// The scope container: basic outline + the resolved domain-scope name (or
/// the ghost variant naming the dangling code).
///
/// Children render inside.
struct DopeScopeOutlineView: View {
    let element: ResolvedElement
    let card: ResolvedScopeCard?
    let environment: DiagramRenderEnvironment
    var ghostCode: String?
    let offset: CGSize
    @Environment(\.diagramSelection) private var selection

    /// Creates a view for a diagram scope card element.
    ///
    /// - Parameters:
    ///   - element: The resolved card element.
    ///   - card: The scope card model, or nil for a ghost.
    ///   - environment: The diagram rendering environment.
    ///   - ghostCode: The code for a ghost card, or nil.
    ///   - offset: The offset in view space; defaults to zero.
    init(
        element: ResolvedElement,
        card: ResolvedScopeCard?,
        environment: DiagramRenderEnvironment,
        ghostCode: String? = nil,
        offset: CGSize = .zero
    ) {
        self.element = element
        self.card = card
        self.environment = environment
        self.ghostCode = ghostCode
        self.offset = offset
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Selection accent: if-guarded so the unset default contributes
            // nothing to the view tree (byte-identity at the frozen sites).
            if selection.selectedElementUuid == element.uuid {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .frame(width: element.frame.width + 6, height: element.frame.height + 6)
                    .position(
                        x: element.frame.midX + offset.width,
                        y: element.frame.midY + offset.height
                    )
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: card == nil ? [6, 4] : []
                    )
                )
                .foregroundStyle(card == nil ? Color.secondary : Color.accentColor.opacity(0.6))
                .frame(width: element.frame.width, height: element.frame.height)
                .position(
                    x: element.frame.midX + offset.width,
                    y: element.frame.midY + offset.height
                )
            HStack(spacing: 6) {
                Text(card?.scopeName ?? "⌀ \(ghostCode ?? element.code)")
                    .font(.system(size: 13, weight: .semibold))
                if let card {
                    Text(card.dopeScopeCode).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(card.resolvedVia).font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                } else {
                    Text("unresolved").font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
            }
            .position(
                x: element.frame.midX + offset.width,
                y: element.frame.minY - 12 + offset.height
            )
            ForEach(element.children, id: \.uuid) { child in
                ResolvedElementView(
                    element: child,
                    environment: environment,
                    offset: offset
                )
            }
        }
    }
}

/// The dbdiagram-style entity card: header tinted by the DOMAIN code's
/// stable hue, entity name + code, property rows name-left/type-right-gray,
/// badge capsules — or the dashed ghost frame naming the dangling code.
struct DopeEntityCardView: View {
    let element: ResolvedElement
    let model: EntityCardModel?
    let environment: DiagramRenderEnvironment
    let ghostCode: String?
    let offset: CGSize
    @Environment(\.diagramSelection) private var selection

    /// Creates a view for a diagram entity card element.
    ///
    /// - Parameters:
    ///   - element: The resolved card element.
    ///   - model: The entity card model, or nil for a ghost.
    ///   - environment: The diagram rendering environment.
    ///   - ghostCode: The code for a ghost card, or nil.
    ///   - offset: The offset in view space; defaults to zero.
    init(
        element: ResolvedElement,
        model: EntityCardModel?,
        environment: DiagramRenderEnvironment,
        ghostCode: String?,
        offset: CGSize = .zero
    ) {
        self.element = element
        self.model = model
        self.environment = environment
        self.ghostCode = ghostCode
        self.offset = offset
    }

    private var headerColor: Color {
        guard let model else { return .secondary }
        return Color(hue: model.headerHue, saturation: 0.55, brightness: 0.72)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                // Table name FIRST — the schema truth. A ghost has no model,
                // so it falls back to the 2-segment binding code that failed
                // to resolve (that path IS the diagnostic there).
                Text(model?.tableName ?? ghostCode ?? element.code)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(model?.entityName ?? "⌀ missing")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .frame(height: environment.cardHeaderHeight - 12)
            .background(model == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(headerColor))

            if let model {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        Text(row.name).font(.system(size: 10, design: .monospaced))
                        ForEach(row.badges, id: \.self) { badge in
                            Text(badge).font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.18))
                                )
                        }
                        Spacer(minLength: 6)
                        Text(row.typeLabel).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: environment.cardRowHeight - 4)
                }
            } else {
                Text("no code-matching entity")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(height: environment.cardRowHeight)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: model == nil ? [4, 3] : []))
                .foregroundStyle(model == nil ? Color.secondary : Color.primary.opacity(0.25))
        )
        // Selection/emphasis reads — if-guarded (and identity-op opacity) so
        // the unset default renders byte-identically at the frozen sites.
        .overlay {
            if selection.selectedElementUuid == element.uuid {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-2)
            }
        }
        .opacity(selection.dimmedElementUuids.contains(element.uuid) ? 0.35 : 1)
        .frame(width: element.frame.width)
        .position(
            x: element.frame.midX + offset.width,
            y: element.frame.midY + offset.height
        )
    }
}

/// The FK edge pass, drawn over everything: a dumb stroker over the
/// resolver's routed orthogonal polylines (rounded corners, radius clamped
/// per corner), with the legacy cubic quarantined as the `routed: false`
/// fallback.
///
/// All geometry decisions live in DiagramEdgeRouter — none here.
struct DiagramEdgeCanvas: View {
    let edges: [ResolvedEdge]
    let environment: DiagramRenderEnvironment
    let offset: CGSize
    @Environment(\.diagramSelection) private var selection

    /// Creates a view for diagram connector edges.
    ///
    /// - Parameters:
    ///   - edges: The edges to render.
    ///   - environment: The diagram rendering environment.
    ///   - offset: The offset in view space; defaults to zero.
    init(
        edges: [ResolvedEdge],
        environment: DiagramRenderEnvironment,
        offset: CGSize = .zero
    ) {
        self.edges = edges
        self.environment = environment
        self.offset = offset
    }

    var body: some View {
        // Read the environment into a let BEFORE the Canvas closure —
        // renderer closures are not tracked observation scopes.
        let highlighted = selection.highlightedElementUuids
        Canvas { context, _ in
            context.translateBy(x: offset.width, y: offset.height)
            // Pass 1: the base pass, iterating in exactly the pre-slot order
            // with the pre-slot style — an empty highlight set leaves this
            // canvas byte-identical to the frozen screenshot output.
            for edge in edges {
                switch edge.origin {
                case .dopeForeignKey:
                    let path =
                        edge.routed && edge.points.count >= 2
                        ? Self.roundedPolyline(edge.points)
                        : Self.legacyCubic(from: edge.from, to: edge.to)
                    // Untouched from the frozen screenshot output: a derived
                    // FK arrow is deliberately quiet.
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.2)
                    )
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: edge.to.x - 2.5,
                                y: edge.to.y - 2.5,
                                width: 5,
                                height: 5
                            )
                        ),
                        with: .color(.secondary)
                    )
                case .connector(_, let style):
                    // A hand-drawn connector carries its own styling — it is
                    // something a person asserted, not something derived, and
                    // it should not read as an FK arrow.
                    let geometry = Self.connectorGeometry(edge: edge, style: style)
                    context.stroke(
                        geometry.path,
                        with: .color(Color(hex: style.strokeColor)),
                        style: StrokeStyle(
                            lineWidth: style.lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: style.lineStyle == .dashed
                                ? [style.lineWidth * 3, style.lineWidth * 2] : []
                        )
                    )
                    for decoration in [
                        DiagramConnectorHeadGeometry.headPath(
                            kind: style.headKind,
                            tip: edge.to,
                            direction: geometry.headDirection,
                            lineWidth: style.lineWidth
                        ),
                        DiagramConnectorHeadGeometry.headPath(
                            kind: style.tailKind,
                            tip: edge.from,
                            direction: geometry.tailDirection,
                            lineWidth: style.lineWidth
                        ),
                    ] {
                        guard let decoration else { continue }
                        if decoration.fill {
                            context.fill(
                                decoration.path,
                                with: .color(Color(hex: style.strokeColor))
                            )
                        } else {
                            context.stroke(
                                decoration.path,
                                with: .color(Color(hex: style.strokeColor)),
                                style: StrokeStyle(
                                    lineWidth: style.lineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        }
                    }
                    if !style.label.isEmpty {
                        let mid = Self.labelPosition(edge: edge, style: style)
                        context.draw(
                            Text(style.label)
                                .font(.system(size: max(9, style.lineWidth * 4)))
                                .foregroundStyle(Color(hex: style.strokeColor)),
                            at: CGPoint(x: mid.x, y: mid.y - max(8, style.lineWidth * 3))
                        )
                    }
                }
            }
            // Pass 2: accent restroke of edges incident to a highlighted
            // element, drawn ABOVE every base edge. Empty set ⇒ zero
            // iterations execute.
            if !highlighted.isEmpty {
                for edge in edges
                where highlighted.contains(edge.fromElementUuid)
                    || highlighted.contains(edge.toElementUuid)
                {
                    let path: Path
                    if case .connector(_, let style) = edge.origin {
                        path = Self.connectorGeometry(edge: edge, style: style).path
                    } else {
                        path =
                            edge.routed && edge.points.count >= 2
                            ? Self.roundedPolyline(edge.points)
                            : Self.legacyCubic(from: edge.from, to: edge.to)
                    }
                    context.stroke(
                        path,
                        with: .color(.accentColor),
                        style: StrokeStyle(lineWidth: 2)
                    )
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: edge.to.x - 3,
                                y: edge.to.y - 3,
                                width: 6,
                                height: 6
                            )
                        ),
                        with: .color(.accentColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A connector's drawn path plus the directions its decorations point.
    ///
    /// The head arrives along the LAST drawn segment, the tail points back out
    /// along the FIRST segment reversed. Never the from→to chord — the chord is
    /// wrong exactly when routing worked.
    ///
    /// routingKind picks the geometry: orthogonal_step is the router's polyline
    /// (cubic when routing declines), straight is the chord, curved is the cubic.
    struct ConnectorGeometry {
        let path: Path
        let headDirection: CGVector
        let tailDirection: CGVector
    }

    /// Computes the geometry for a connector edge.
    ///
    /// - Parameters:
    ///   - edge: The edge whose geometry to compute.
    ///   - style: The connector style.
    /// - Returns: The computed connector geometry.
    static func connectorGeometry(
        edge: ResolvedEdge,
        style: ResolvedConnector
    ) -> ConnectorGeometry {
        switch style.routingKind {
        case .straight:
            var path = Path()
            path.move(to: edge.from)
            path.addLine(to: edge.to)
            return ConnectorGeometry(
                path: path,
                headDirection: CGVector(
                    dx: edge.to.x - edge.from.x,
                    dy: edge.to.y - edge.from.y
                ),
                tailDirection: CGVector(
                    dx: edge.from.x - edge.to.x,
                    dy: edge.from.y - edge.to.y
                )
            )
        case .curved:
            // The legacy cubic's tangents are horizontal at both ends by
            // construction (controls offset only in x).
            let sign: CGFloat = edge.to.x >= edge.from.x ? 1 : -1
            return ConnectorGeometry(
                path: Self.legacyCubic(from: edge.from, to: edge.to),
                headDirection: CGVector(dx: sign, dy: 0),
                tailDirection: CGVector(dx: -sign, dy: 0)
            )
        case .orthogonalStep:
            if edge.routed, edge.points.count >= 2 {
                let points = edge.points
                return ConnectorGeometry(
                    path: Self.roundedPolyline(points),
                    headDirection: CGVector(
                        dx: points[points.count - 1].x - points[points.count - 2].x,
                        dy: points[points.count - 1].y - points[points.count - 2].y
                    ),
                    tailDirection: CGVector(
                        dx: points[0].x - points[1].x,
                        dy: points[0].y - points[1].y
                    )
                )
            }
            let sign: CGFloat = edge.to.x >= edge.from.x ? 1 : -1
            return ConnectorGeometry(
                path: Self.legacyCubic(from: edge.from, to: edge.to),
                headDirection: CGVector(dx: sign, dy: 0),
                tailDirection: CGVector(dx: -sign, dy: 0)
            )
        }
    }

    /// Returns the label position on a connector.
    ///
    /// The position is the ARCLENGTH midpoint of the drawn edge, never a
    /// terminal point, so the label cannot crash into the arrowhead.
    ///
    /// - Parameters:
    ///   - edge: The edge whose label position to compute.
    ///   - style: The connector style.
    /// - Returns: The label position in diagram space.
    static func labelPosition(edge: ResolvedEdge, style: ResolvedConnector) -> CGPoint {
        switch style.routingKind {
        case .straight:
            return CGPoint(
                x: (edge.from.x + edge.to.x) / 2,
                y: (edge.from.y + edge.to.y) / 2
            )
        case .curved:
            // The legacy cubic at t = 0.5.
            let dx = max(40, abs(edge.to.x - edge.from.x) / 2)
            let lead = edge.to.x >= edge.from.x ? dx : -dx
            let c1 = CGPoint(x: edge.from.x + lead, y: edge.from.y)
            let c2 = CGPoint(x: edge.to.x - lead, y: edge.to.y)
            return CGPoint(
                x: 0.125 * (edge.from.x + 3 * c1.x + 3 * c2.x + edge.to.x),
                y: 0.125 * (edge.from.y + 3 * c1.y + 3 * c2.y + edge.to.y)
            )
        case .orthogonalStep:
            let points =
                edge.routed && edge.points.count >= 2
                ? edge.points : [edge.from, edge.to]
            var total: CGFloat = 0
            for index in 0..<(points.count - 1) {
                total += hypot(
                    points[index + 1].x - points[index].x,
                    points[index + 1].y - points[index].y
                )
            }
            guard total > 0 else { return points[0] }
            var remaining = total / 2
            for index in 0..<(points.count - 1) {
                let segment = hypot(
                    points[index + 1].x - points[index].x,
                    points[index + 1].y - points[index].y
                )
                if remaining <= segment, segment > 0 {
                    let t = remaining / segment
                    return CGPoint(
                        x: points[index].x + (points[index + 1].x - points[index].x) * t,
                        y: points[index].y + (points[index + 1].y - points[index].y) * t
                    )
                }
                remaining -= segment
            }
            return points[points.count / 2]
        }
    }

    /// Rounded-corner orthogonal polyline.
    ///
    /// Radius clamps per corner to half the shorter adjacent segment — the
    /// Constructs a path with rounded corners for polyline points.
    ///
    /// The router merges collinear runs so segment lengths are honest and short jogs
    /// never invert visually.
    ///
    /// - Parameter points: The polyline points in order.
    /// - Returns: A path with rounded corners at each point.
    static func roundedPolyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let corner = points[index]
            let next = points[index + 1]
            let inLength = hypot(corner.x - previous.x, corner.y - previous.y)
            let outLength = hypot(next.x - corner.x, next.y - corner.y)
            let radius = min(8, inLength / 2, outLength / 2)
            if radius > 0.1 {
                path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
            } else {
                path.addLine(to: corner)
            }
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// Constructs a path using the legacy straight-curve algorithm.
    ///
    /// This pre-routing v1 algorithm is kept verbatim and drawn only when the router
    /// declined the edge.
    ///
    /// - Parameters:
    ///   - from: The start point.
    ///   - to: The end point.
    /// - Returns: A path for the legacy cubic curve.
    static func legacyCubic(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        let dx = max(40, abs(to.x - from.x) / 2)
        let lead = to.x >= from.x ? dx : -dx
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x + lead, y: from.y),
            control2: CGPoint(x: to.x - lead, y: to.y)
        )
        return path
    }
}

extension Color {
    /// Creates a color from a hex string with a gray fallback.
    ///
    /// Parses #rgb, #rrggbb, or #rrggbbaa hex strings and falls back to gray on error.
    ///
    /// - Parameter hex: A hex color string.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        var rgba: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&rgba) else {
            self = .gray
            return
        }
        let hasAlpha = value.count == 8
        let divisor = 255.0
        if hasAlpha {
            self = Color(
                red: Double((rgba >> 24) & 0xFF) / divisor,
                green: Double((rgba >> 16) & 0xFF) / divisor,
                blue: Double((rgba >> 8) & 0xFF) / divisor,
                opacity: Double(rgba & 0xFF) / divisor
            )
        } else {
            self = Color(
                red: Double((rgba >> 16) & 0xFF) / divisor,
                green: Double((rgba >> 8) & 0xFF) / divisor,
                blue: Double(rgba & 0xFF) / divisor
            )
        }
    }
}
#endif
