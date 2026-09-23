import Foundation
import CoreGraphics

/// The domain pill filter, as a projection of the RESOLVED output.
///
/// The tree is the document and the filter is a view of it: hide the unselected domains'
/// cards in the resolve, drop the edges left without both endpoints, and re-derive the content
/// bounds so Fit still frames what is drawn. A pill toggle writes nothing and re-resolves
/// nothing, so it cannot delete and recreate element rows under a gesture in flight;
/// `DiagramWorkspace` keeps the filter-blind resolve and re-projects from it.
enum DiagramDomainFilter {

    /// Filters a diagram to show only the selected domains.
    ///
    /// An empty domain set means "every domain", so "all selected" and "none selected" are one
    /// state. Hides unselected domain cards, drops edges without both endpoints, and re-derives
    /// content bounds.
    ///
    /// - Parameters:
    ///   - domains: The set of domain codes to show; empty means show all.
    ///   - resolved: The diagram to filter.
    /// - Returns: A filtered diagram showing only selected domains.
    static func apply(_ domains: Set<String>, to resolved: ResolvedDiagram) -> ResolvedDiagram {
        guard !domains.isEmpty else { return resolved }

        var kept: Set<String> = []
        let topLevel = resolved.topLevel.compactMap { keep($0, domains: domains, kept: &kept) }
        // An edge (FK arrow or drawn connector) survives only with both of
        // its endpoints; a half-anchored line would point into empty space.
        let edges = resolved.edges.filter {
            kept.contains($0.fromElementUuid) && kept.contains($0.toElementUuid)
        }
        return ResolvedDiagram(
            contentBounds: bounds(topLevel: topLevel, edges: edges) ?? resolved.contentBounds,
            topLevel: topLevel,
            edges: edges,
            environment: resolved.environment
        )
    }

    /// Recursively filters an element, removing entity cards not in the domain selection.
    ///
    /// Drawings and text survive (they belong to the user); ghost cards survive (they have no
    /// domain). Tracks kept element uuids for edge filtering.
    ///
    /// - Parameters:
    ///   - element: The element to filter.
    ///   - domains: The set of domain codes to keep.
    ///   - kept: Updated to track which elements are kept.
    /// - Returns: The filtered element, or nil if filtered out.
    private static func keep(
        _ element: ResolvedElement,
        domains: Set<String>,
        kept: inout Set<String>
    ) -> ResolvedElement? {
        if case .entityCard(let model) = element.kind,
            !domains.contains(model.domainCode)
        {
            return nil
        }
        let children = element.children.compactMap { keep($0, domains: domains, kept: &kept) }
        kept.insert(element.uuid)
        return ResolvedElement(
            uuid: element.uuid,
            code: element.code,
            name: element.name,
            frame: element.frame,
            elementZ: element.elementZ,
            kind: element.kind,
            children: children,
            accumulatedCenter: element.accumulatedCenter,
            accumulatedScale: element.accumulatedScale
        )
    }

    /// Computes the union of all element frames and edge points.
    ///
    /// Recomputes the resolver's contentBounds contract over the surviving filtered elements
    /// and edges.
    ///
    /// - Parameters:
    ///   - topLevel: The filtered top-level elements.
    ///   - edges: The filtered edges with both endpoints.
    /// - Returns: The union of all drawn content, or nil if empty.
    private static func bounds(
        topLevel: [ResolvedElement],
        edges: [ResolvedEdge]
    ) -> CGRect? {
        var union: CGRect?
        func absorb(_ rect: CGRect) {
            union = union.map { $0.union(rect) } ?? rect
        }
        func walk(_ element: ResolvedElement) {
            absorb(element.frame)
            element.children.forEach(walk)
        }
        topLevel.forEach(walk)
        for edge in edges {
            for point in edge.points {
                absorb(CGRect(origin: point, size: .zero))
            }
        }
        return union
    }
}
