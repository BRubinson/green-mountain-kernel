import CoreGraphics
import Foundation

/// Organize-by-closeness: one deterministic pass over the entity cards that
/// returns plain `elementUpdate` mutations, so the organize button flows
/// through the SAME edit-session → committer → reducer funnel as a drag (no
/// second write path, CAS for free).
///
/// Kit-resident because the one constant that makes layouts routable is
/// internal here: the router inflates every obstacle by
/// `DiagramResolver.edgeRoutingPadding` per side, so card gaps below
/// `2 × padding + 2` close the A* corridors entirely and edges degrade to
/// the legacy cubic fallback. `minSeparation` is DERIVED from that value —
/// never a hand-copied 26 — so a padding change breaks the fixture loudly.
///
/// Determinism is a correctness requirement (same input → same layout):
/// fixed iteration counts, uuid-sorted traversal, no RNG, no wall-clock;
/// coincident centers tie-break by an FNV-1a angle from the uuid.
public enum DiagramOrganizer {

    /// The corridor floor: below this gap the router's per-side inflation
    /// leaves no corridor between two cards.
    public static var minSeparation: CGFloat {
        CGFloat(DiagramResolver.edgeRoutingPadding) * 2 + 2
    }

    static let forceIterations = 120
    static let separationSweeps = 40

    /// New diagram-space centers for every entity card (present or ghost),
    /// keyed by element uuid. Only cards that moved appear.
    public static func newCenters(for resolved: ResolvedDiagram) -> [String: CGPoint] {
        struct Card {
            let uuid: String
            var center: CGPoint
            let size: CGSize
        }
        var cards: [Card] = []
        func collect(_ element: ResolvedElement) {
            switch element.kind {
            case .entityCard, .absentEntity:
                cards.append(Card(uuid: element.uuid,
                                  center: CGPoint(x: element.frame.midX,
                                                  y: element.frame.midY),
                                  size: element.frame.size))
            case .layer, .stroke, .shape, .text, .connector, .umlNode,
                 .scopeCard, .absentScope:
                // Organize lays out ENTITY CARDS. Hand-placed drawing
                // content (UML nodes included) keeps the position it was
                // drawn at, and a connector has no position of its own at
                // all — it follows whatever its endpoints do.
                break
            }
            for child in element.children { collect(child) }
        }
        for element in resolved.topLevel { collect(element) }
        cards.sort { $0.uuid < $1.uuid }
        guard cards.count > 1 else { return [:] }

        let original = Dictionary(uniqueKeysWithValues: cards.map { ($0.uuid, $0.center) })
        var index: [String: Int] = [:]
        for (i, card) in cards.enumerated() { index[card.uuid] = i }

        // FK adjacency (uuid-index pairs, deduped, sorted).
        var springs: [(Int, Int)] = []
        var seen: Set<String> = []
        for edge in resolved.edges {
            guard let a = index[edge.fromElementUuid],
                  let b = index[edge.toElementUuid], a != b else { continue }
            let key = a < b ? "\(a)|\(b)" : "\(b)|\(a)"
            if seen.insert(key).inserted { springs.append((min(a, b), max(a, b))) }
        }
        springs.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }

        /// Deterministic unit vector for coincident centers.
        func tieBreak(_ uuid: String) -> CGVector {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in uuid.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
            let angle = Double(hash % 3600) / 3600.0 * 2 * .pi
            return CGVector(dx: cos(angle), dy: sin(angle))
        }

        // Force pass: springs attract toward an ideal center distance,
        // near/overlapping frames repel. Forces accumulate per iteration and
        // apply once (Jacobi-style), so pair order cannot bias the result.
        for _ in 0..<forceIterations {
            var force = [CGVector](repeating: .zero, count: cards.count)
            for (a, b) in springs {
                let ideal = (cards[a].size.width + cards[b].size.width) / 2
                    + minSeparation + 40
                let dx = cards[b].center.x - cards[a].center.x
                let dy = cards[b].center.y - cards[a].center.y
                let distance = max(1, hypot(dx, dy))
                let pull = (distance - ideal) * 0.02
                let ux = dx / distance, uy = dy / distance
                force[a].dx += ux * pull; force[a].dy += uy * pull
                force[b].dx -= ux * pull; force[b].dy -= uy * pull
            }
            for a in 0..<cards.count {
                for b in (a + 1)..<cards.count {
                    let wantX = (cards[a].size.width + cards[b].size.width) / 2 + minSeparation
                    let wantY = (cards[a].size.height + cards[b].size.height) / 2 + minSeparation
                    var dx = cards[b].center.x - cards[a].center.x
                    var dy = cards[b].center.y - cards[a].center.y
                    if dx == 0 && dy == 0 {
                        let jitter = tieBreak(cards[a].uuid)
                        dx = jitter.dx; dy = jitter.dy
                    }
                    let overlapX = wantX - abs(dx)
                    let overlapY = wantY - abs(dy)
                    guard overlapX > 0, overlapY > 0 else { continue }
                    let push = min(overlapX, overlapY) * 0.12
                    let distance = max(1, hypot(dx, dy))
                    let ux = dx / distance, uy = dy / distance
                    force[a].dx -= ux * push; force[a].dy -= uy * push
                    force[b].dx += ux * push; force[b].dy += uy * push
                }
            }
            for i in 0..<cards.count {
                cards[i].center.x += force[i].dx
                cards[i].center.y += force[i].dy
            }
        }

        // Separation post-pass: hard-guarantee the corridor floor on the
        // axis of least overlap, uuid-pair order, fixed sweep budget.
        for _ in 0..<separationSweeps {
            var moved = false
            for a in 0..<cards.count {
                for b in (a + 1)..<cards.count {
                    let wantX = (cards[a].size.width + cards[b].size.width) / 2 + minSeparation
                    let wantY = (cards[a].size.height + cards[b].size.height) / 2 + minSeparation
                    var dx = cards[b].center.x - cards[a].center.x
                    var dy = cards[b].center.y - cards[a].center.y
                    if dx == 0 && dy == 0 {
                        let jitter = tieBreak(cards[a].uuid)
                        dx = jitter.dx * 0.5; dy = jitter.dy * 0.5
                    }
                    let overlapX = wantX - abs(dx)
                    let overlapY = wantY - abs(dy)
                    guard overlapX > 0, overlapY > 0 else { continue }
                    moved = true
                    if overlapX <= overlapY {
                        let push = overlapX / 2 + 0.5
                        let sign: CGFloat = dx >= 0 ? 1 : -1
                        cards[index[cards[a].uuid]!].center.x -= sign * push
                        cards[index[cards[b].uuid]!].center.x += sign * push
                    } else {
                        let push = overlapY / 2 + 0.5
                        let sign: CGFloat = dy >= 0 ? 1 : -1
                        cards[index[cards[a].uuid]!].center.y -= sign * push
                        cards[index[cards[b].uuid]!].center.y += sign * push
                    }
                }
            }
            if !moved { break }
        }

        var result: [String: CGPoint] = [:]
        for card in cards {
            let before = original[card.uuid]!
            if abs(card.center.x - before.x) > 0.5 || abs(card.center.y - before.y) > 0.5 {
                result[card.uuid] = card.center
            }
        }
        return result
    }

    /// The organize batch: one `elementUpdate` per moved card, diagram-space
    /// deltas converted to parent-space writes via the same divisor rule as
    /// `DiagramDrag.moveMutation`.
    public static func organize(_ resolved: ResolvedDiagram,
                                tree: DiagramTree) -> [DiagramMutation] {
        let centers = newCenters(for: resolved)
        guard !centers.isEmpty else { return [] }
        var mutations: [DiagramMutation] = []
        for (uuid, newCenter) in centers.sorted(by: { $0.key < $1.key }) {
            guard let element = resolved.element(uuid: uuid),
                  let node = DiagramTreeReducer.findNode(uuid, in: tree.elements)
            else { continue }
            let delta = CGSize(
                width: newCenter.x - element.frame.midX,
                height: newCenter.y - element.frame.midY)
            mutations.append(DiagramDrag.moveMutation(node: node, resolved: element,
                                                      by: delta))
        }
        return mutations
    }
}
