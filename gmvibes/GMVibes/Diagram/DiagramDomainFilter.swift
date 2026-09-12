import Foundation
import CoreGraphics
import GMCCDaemonKit

/// The domain pill filter, as a projection of the RESOLVED output.
///
/// It used to be a tree rebuild: toggling a pill re-scaffolded the whole
/// canvas from the dope tree through `DopeCanvasLayout`. That is free against
/// a throwaway document and catastrophic against a db-backed one — every pill
/// click would be a delete-and-recreate of every element row, one revision
/// per click, and every uuid re-minted under whatever gesture was in flight.
///
/// So the tree is the document and the filter is a view of it: hide the
/// unselected domains' cards in the resolve, drop the edges that no longer
/// have both endpoints, and re-derive the content bounds so Fit still frames
/// what is actually drawn. Nothing is written, nothing is re-resolved (no A*
/// re-run) — `DiagramWorkspace` keeps the filter-blind resolve and
/// re-projects from it.
enum DiagramDomainFilter {

    /// An empty selection means "every domain" — the same convention the
    /// pills menu uses, so "all selected" and "none selected" are one state.
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
            topLevel: topLevel, edges: edges, environment: resolved.environment)
    }

    /// Drop entity cards outside the selection; every other kind survives
    /// (drawings and text belong to the user, not to a domain, and a ghost
    /// card has no domain to test).
    private static func keep(_ element: ResolvedElement, domains: Set<String>,
                             kept: inout Set<String>) -> ResolvedElement? {
        if case .entityCard(let model) = element.kind,
           !domains.contains(model.domainCode) {
            return nil
        }
        let children = element.children.compactMap { keep($0, domains: domains, kept: &kept) }
        kept.insert(element.uuid)
        return ResolvedElement(
            uuid: element.uuid, code: element.code, name: element.name,
            frame: element.frame, elementZ: element.elementZ, kind: element.kind,
            children: children, accumulatedCenter: element.accumulatedCenter,
            accumulatedScale: element.accumulatedScale)
    }

    /// The union of what is still drawn — the resolver's own contentBounds
    /// contract, recomputed over the survivors.
    private static func bounds(topLevel: [ResolvedElement],
                               edges: [ResolvedEdge]) -> CGRect? {
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
