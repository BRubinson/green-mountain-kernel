#if canImport(SwiftUI)
import SwiftUI

/// The scene-composition half of the old DiagramCanvasView: the
/// painter-ordered ZStack (underlay → cards/scopes → edge canvas → overlay)
/// at a HOST-SUPPLIED offset. Deliberately carries NO background paint, NO
/// frame, and NO colorScheme override — those are screenshot framing, and
/// they stay on `DiagramCanvasView`. An interactive host composes this under
/// its own viewport root, passes its pan-derived diagram-space offset here
/// (per the coordinate contract: the offset is applied INSIDE each Canvas
/// and on each .position, never as a `.offset` modifier), and applies zoom
/// as an outer `.scaleEffect` — the components stay zoom-unaware.
///
/// The `underlay`/`overlay` slots default to `EmptyView`, so slot-less use
/// composes the identical view tree the pre-split DiagramCanvasView built.
public struct DiagramSceneView<Underlay: View, Overlay: View>: View {
    public let resolved: ResolvedDiagram
    public let offset: CGSize
    private let underlay: Underlay
    private let overlay: Overlay

    public init(resolved: ResolvedDiagram, offset: CGSize,
                @ViewBuilder underlay: () -> Underlay = { EmptyView() },
                @ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.resolved = resolved
        self.offset = offset
        self.underlay = underlay()
        self.overlay = overlay()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            underlay
            // Depth-first painter order; siblings arrive pre-sorted by
            // (elementZ, code) from the resolver.
            ForEach(resolved.topLevel, id: \.uuid) { element in
                ResolvedElementView(element: element,
                                    environment: resolved.environment,
                                    offset: offset)
            }
            DiagramEdgeCanvas(edges: resolved.edges,
                              environment: resolved.environment,
                              offset: offset)
            overlay
        }
    }
}
#endif
