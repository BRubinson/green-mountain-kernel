#if canImport(SwiftUI)
import SwiftUI

/// Scene composition: the painter-ordered ZStack (underlay → cards/scopes → edge
/// canvas → overlay) at a HOST-SUPPLIED offset. It carries no background paint,
/// frame or colorScheme override — that screenshot framing belongs to
/// `DiagramCanvasView`. A host passes its pan-derived diagram-space offset here
/// (the coordinate contract applies: INSIDE each Canvas and on each `.position`,
/// never as a `.offset` modifier) and applies zoom as an outer `.scaleEffect`, so
/// the components stay zoom-unaware. The `underlay`/`overlay` slots default to
/// `EmptyView`.
struct DiagramSceneView<Underlay: View, Overlay: View>: View {
    let resolved: ResolvedDiagram
    let offset: CGSize
    private let underlay: Underlay
    private let overlay: Overlay

    init(
        resolved: ResolvedDiagram,
        offset: CGSize,
        @ViewBuilder underlay: () -> Underlay = { EmptyView() },
        @ViewBuilder overlay: () -> Overlay = { EmptyView() }
    ) {
        self.resolved = resolved
        self.offset = offset
        self.underlay = underlay()
        self.overlay = overlay()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            underlay
            // Depth-first painter order; siblings arrive pre-sorted by
            // (elementZ, code) from the resolver.
            ForEach(resolved.topLevel, id: \.uuid) { element in
                ResolvedElementView(
                    element: element,
                    environment: resolved.environment,
                    offset: offset
                )
            }
            DiagramEdgeCanvas(
                edges: resolved.edges,
                environment: resolved.environment,
                offset: offset
            )
            overlay
        }
    }
}
#endif
