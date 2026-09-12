import CoreGraphics
import Foundation

/// Obstacle-avoiding orthogonal edge routing: the three-stage connector
/// pipeline (Wybrow/Marriott/Stuckey, GD'09) behind ONE pure entry point —
/// orthogonal visibility graph → multi-terminal A* with bend costs →
/// deterministic corridor nudging.
///
/// The visibility graph is encoded as an implicit integer lattice
/// (`RoutingField`): the sorted-distinct interesting coordinates of every
/// inflated obstacle plus every anchor/stub coordinate, with per-segment
/// blocked tests against inflated-rect STRICT interiors (ring-hugging
/// segments are free). All routing arithmetic is Int64 at 1/256 pt —
/// determinism is a correctness requirement here (screenshots must diff
/// clean across runs, same rule as `DiagramPalette`'s FNV comment), and an
/// integer domain kills float slivers and hash-order hazards by construction
/// rather than by reviewer discipline. Floats exist only at the boundary.
///
/// Anchor sides are an OUTPUT of routing: each endpoint contributes both its
/// left and right candidate terminals (multi-source/multi-target A* via
/// virtual super-source/super-target arcs that carry the escape stubs — the
/// stubs are never searched), and the winning terminal pair back-derives the
/// sides. An endpoint whose candidate stubs are all swallowed by a
/// neighbor's inflated ring, or a search that exhausts the lattice, yields
/// `routed: false` — the caller keeps its legacy straight pair.
///
/// SwiftUI-free on purpose (Foundation + CoreGraphics, outside any
/// `canImport(SwiftUI)` guard): the router is unit-tested in plain XCTest
/// and auto-vendored to GMVibes with zero manifest changes.
public enum DiagramEdgeRouter {

    // MARK: - Public surface

    public struct EdgeRequest: Sendable {
        /// UNinflated diagram-space frame of the source card.
        public let fromFrame: CGRect
        /// UNinflated diagram-space frame of the target card.
        public let toFrame: CGRect
        /// Diagram-space y of the FK property ROW on the source card — the
        /// edge leaves at the row, not the card's midY.
        public let sourceRowY: CGFloat
        /// `domain.entity.property` — nudge/order key part 1.
        public let propertyRef: String
        /// Order key part 2: propertyRef alone is NOT a total order
        /// (duplicate cards binding one entity emit identical refs).
        public let fromElementUuid: String

        public init(fromFrame: CGRect, toFrame: CGRect, sourceRowY: CGFloat,
                    propertyRef: String, fromElementUuid: String) {
            self.fromFrame = fromFrame
            self.toFrame = toFrame
            self.sourceRowY = sourceRowY
            self.propertyRef = propertyRef
            self.fromElementUuid = fromElementUuid
        }
    }

    public struct Obstacle: Sendable {
        /// UNinflated diagram-space card frame.
        public let frame: CGRect
        /// Accumulated transform scale — inflation = `padding * scale`, so
        /// corridors survive scaled subtrees.
        public let scale: CGFloat

        public init(frame: CGRect, scale: CGFloat) {
            self.frame = frame
            self.scale = scale
        }
    }

    public struct RoutedPolyline: Sendable {
        /// When `routed`: >= 2 diagram-space points, orthogonal,
        /// collinear-merged. When not: EMPTY — the caller substitutes its
        /// legacy straight pair.
        public let points: [CGPoint]
        public let routed: Bool
    }

    /// Cost per 90° turn, in points. Bends dominate legibility.
    static let bendPenaltyPoints: Double = 15
    /// Parallel-offset spacing for edges sharing a corridor, in points.
    static let nudgeSpacingPoints: Double = 4

    /// Routes every request against every obstacle. Requests are routed in
    /// array order (the resolver's emission order, already uuid-sorted);
    /// output index i corresponds to input index i.
    /// Coordinates past this bound (or non-finite) come from hostile db
    /// geometry — routing degrades instead of letting `Int64(Double)` trap.
    private static let saneLimit: CGFloat = 1_000_000_000

    private static func isSane(_ value: CGFloat) -> Bool {
        value.isFinite && abs(value) <= saneLimit
    }

    private static func isSane(_ rect: CGRect) -> Bool {
        isSane(rect.minX) && isSane(rect.minY) && isSane(rect.maxX) && isSane(rect.maxY)
    }

    public static func route(edges: [EdgeRequest], obstacles: [Obstacle],
                             padding: CGFloat = 12) -> [RoutedPolyline] {
        guard !edges.isEmpty else { return [] }
        // Sanitize BEFORE the integer boundary: db doubles are unvalidated,
        // and a NaN/inf/huge coordinate must degrade (obstacle dropped, edge
        // falls back to routed:false), never crash the render.
        let obstacles = obstacles.filter { isSane($0.frame) && isSane($0.scale) }
        let rects = obstacles.map {
            QRect(inflating: $0.frame, by: padding * max($0.scale, 0))
        }

        // Candidate terminals per edge, up front — their coordinates seed
        // the shared lattice (all anchors and stub termini are graph
        // coordinates by construction).
        let candidates: [(sources: [Terminal], targets: [Terminal])] = edges.map { edge in
            guard isSane(edge.fromFrame), isSane(edge.toFrame),
                  isSane(edge.sourceRowY) else { return ([], []) }
            let srcRing = ownRing(for: edge.fromFrame, obstacles: obstacles,
                                  rects: rects, padding: padding)
            let tgtRing = ownRing(for: edge.toFrame, obstacles: obstacles,
                                  rects: rects, padding: padding)
            let rowY = Quant.q(edge.sourceRowY)
            let midY = Quant.q(edge.toFrame.midY)
            let sources = [
                Terminal(anchor: QPoint(x: Quant.q(edge.fromFrame.minX), y: rowY),
                         terminus: QPoint(x: srcRing.minX, y: rowY)),
                Terminal(anchor: QPoint(x: Quant.q(edge.fromFrame.maxX), y: rowY),
                         terminus: QPoint(x: srcRing.maxX, y: rowY)),
            ].filter { valid($0, ownRing: srcRing, rects: rects) }
            let targets = [
                Terminal(anchor: QPoint(x: Quant.q(edge.toFrame.minX), y: midY),
                         terminus: QPoint(x: tgtRing.minX, y: midY)),
                Terminal(anchor: QPoint(x: Quant.q(edge.toFrame.maxX), y: midY),
                         terminus: QPoint(x: tgtRing.maxX, y: midY)),
            ].filter { valid($0, ownRing: tgtRing, rects: rects) }
            return (sources, targets)
        }

        var extraXs: [Int64] = []
        var extraYs: [Int64] = []
        for set in candidates {
            for terminal in set.sources + set.targets {
                extraXs.append(terminal.terminus.x)
                extraYs.append(terminal.terminus.y)
            }
        }
        let field = RoutingField(rects: rects, extraXs: extraXs, extraYs: extraYs)
        let bendQ = Quant.q(bendPenaltyPoints)

        var paths: [[QPoint]?] = candidates.map { set in
            guard !set.sources.isEmpty, !set.targets.isEmpty else { return nil }
            return PathSearch.route(sources: set.sources, targets: set.targets,
                                    field: field, bendPenaltyQ: bendQ)
                .map(simplify)
        }

        TrackAllocator.nudge(&paths, edges: edges, field: field,
                             spacingQ: Quant.q(nudgeSpacingPoints))

        return paths.map { path in
            guard let path else { return RoutedPolyline(points: [], routed: false) }
            let merged = simplify(path)
            return RoutedPolyline(points: merged.map { $0.cgPoint }, routed: true)
        }
    }

    // MARK: - Terminals

    struct Terminal {
        /// On the card border — the polyline's real endpoint.
        let anchor: QPoint
        /// On the card's own inflated ring — the lattice node the escape
        /// stub reaches. Never searched; prepended/appended by construction.
        let terminus: QPoint

        var stubLength: Int64 { abs(anchor.x - terminus.x) + abs(anchor.y - terminus.y) }
    }

    /// The endpoint's own inflated ring. The card IS an obstacle; matching
    /// by quantized frame recovers its scale-inflated rect. A frame with no
    /// obstacle entry (defensive) gets a scale-1 ring.
    private static func ownRing(for frame: CGRect, obstacles: [Obstacle],
                                rects: [QRect], padding: CGFloat) -> QRect {
        let q = QRect(inflating: frame, by: 0)
        for (index, obstacle) in obstacles.enumerated()
        where QRect(inflating: obstacle.frame, by: 0) == q {
            return rects[index]
        }
        return QRect(inflating: frame, by: padding)
    }

    /// A candidate dies when its stub terminus is strictly inside ANY ring
    /// other than its own (cards closer than 2×padding — the enclosed-anchor
    /// fallback case), or when the stub SEGMENT crosses another ring's
    /// interior (a card small enough to sit between anchor and terminus
    /// would otherwise be skewered — stubs are never searched, so this is
    /// their only blocked test). Both checked cheaply before search.
    private static func valid(_ terminal: Terminal, ownRing: QRect,
                              rects: [QRect]) -> Bool {
        let y = terminal.terminus.y
        let lo = min(terminal.anchor.x, terminal.terminus.x)
        let hi = max(terminal.anchor.x, terminal.terminus.x)
        for rect in rects where rect != ownRing {
            if rect.strictlyContains(terminal.terminus) { return false }
            if rect.minY < y && y < rect.maxY && lo < rect.maxX && hi > rect.minX {
                return false
            }
        }
        return true
    }

    // MARK: - Simplify

    /// Drop zero-length segments, merge collinear runs — the view's corner
    /// clamp must see honest segment lengths.
    static func simplify(_ points: [QPoint]) -> [QPoint] {
        var result: [QPoint] = []
        for point in points {
            if result.last == point { continue }
            if result.count >= 2 {
                let a = result[result.count - 2], b = result[result.count - 1]
                if (a.x == b.x && b.x == point.x) || (a.y == b.y && b.y == point.y) {
                    result[result.count - 1] = point
                    continue
                }
            }
            result.append(point)
        }
        return result
    }
}

// MARK: - Quant — the only float ↔ integer boundary (1/256 pt)

enum Quant {
    static func q(_ value: CGFloat) -> Int64 { Int64((value * 256).rounded()) }
    static func floorQ(_ value: CGFloat) -> Int64 { Int64((value * 256).rounded(.down)) }
    static func ceilQ(_ value: CGFloat) -> Int64 { Int64((value * 256).rounded(.up)) }
    static func dq(_ value: Int64) -> CGFloat { CGFloat(value) / 256 }
}

struct QPoint: Equatable {
    var x: Int64
    var y: Int64

    var cgPoint: CGPoint { CGPoint(x: Quant.dq(x), y: Quant.dq(y)) }
}

struct QRect: Equatable {
    var minX: Int64
    var minY: Int64
    var maxX: Int64
    var maxY: Int64

    /// Inflated corners round OUTWARD so blocking is conservative and exact.
    init(inflating frame: CGRect, by pad: CGFloat) {
        minX = Quant.floorQ(frame.minX - pad)
        minY = Quant.floorQ(frame.minY - pad)
        maxX = Quant.ceilQ(frame.maxX + pad)
        maxY = Quant.ceilQ(frame.maxY + pad)
    }

    func strictlyContains(_ p: QPoint) -> Bool {
        p.x > minX && p.x < maxX && p.y > minY && p.y < maxY
    }
}

// MARK: - RoutingField — the implicit orthogonal visibility graph

/// Sorted-distinct interesting coordinates + per-segment open flags. Same
/// node set (coordinate intersections outside inflated obstacles) and edge
/// set (unblocked axis-aligned neighbor segments) as an explicit visibility
/// graph — matrix-encoded, adjacency computed O(1), zero hash iteration.
/// Blocking tests use STRICT interiors with half-open interval logic, so
/// segments exactly on an inflated boundary are free (edges hug the ring)
/// and overlapping obstacles simply OR together — degenerate hand-layouts
/// (overlapping cards, zero-gap stacks) degrade gracefully.
struct RoutingField {
    let xs: [Int64]
    let ys: [Int64]
    let rects: [QRect]
    /// hOpen[yi * (xs.count-1) + xi]: segment (xs[xi],ys[yi])→(xs[xi+1],ys[yi]).
    private var hOpen: [Bool]
    /// vOpen[xi * (ys.count-1) + yi]: segment (xs[xi],ys[yi])→(xs[xi],ys[yi+1]).
    private var vOpen: [Bool]

    init(rects: [QRect], extraXs: [Int64], extraYs: [Int64]) {
        self.rects = rects
        var allXs = extraXs
        var allYs = extraYs
        for rect in rects {
            allXs.append(rect.minX); allXs.append(rect.maxX)
            allYs.append(rect.minY); allYs.append(rect.maxY)
        }
        // Sort-then-unique on arrays: dedup is integer equality, order is
        // total — no Set involved.
        allXs.sort(); allYs.sort()
        var xs: [Int64] = []
        for x in allXs where xs.last != x { xs.append(x) }
        var ys: [Int64] = []
        for y in allYs where ys.last != y { ys.append(y) }
        self.xs = xs
        self.ys = ys

        var hOpen = [Bool](repeating: true, count: ys.count * max(xs.count - 1, 0))
        var vOpen = [Bool](repeating: true, count: xs.count * max(ys.count - 1, 0))
        for yi in ys.indices {
            let y = ys[yi]
            for xi in 0..<(max(xs.count - 1, 0)) {
                let blocked = rects.contains {
                    $0.minY < y && y < $0.maxY && xs[xi] < $0.maxX && xs[xi + 1] > $0.minX
                }
                if blocked { hOpen[yi * (xs.count - 1) + xi] = false }
            }
        }
        for xi in xs.indices {
            let x = xs[xi]
            for yi in 0..<(max(ys.count - 1, 0)) {
                let blocked = rects.contains {
                    $0.minX < x && x < $0.maxX && ys[yi] < $0.maxY && ys[yi + 1] > $0.minY
                }
                if blocked { vOpen[xi * (ys.count - 1) + yi] = false }
            }
        }
        self.hOpen = hOpen
        self.vOpen = vOpen
    }

    func xIndex(of x: Int64) -> Int? { binarySearch(xs, x) }
    func yIndex(of y: Int64) -> Int? { binarySearch(ys, y) }

    func horizontalOpen(yi: Int, fromXi xi: Int) -> Bool {
        hOpen[yi * (xs.count - 1) + xi]
    }

    func verticalOpen(xi: Int, fromYi yi: Int) -> Bool {
        vOpen[xi * (ys.count - 1) + yi]
    }

    /// Free perpendicular distance from a run at `coordinate` spanning
    /// (lo, hi) to the nearest inflated boundary on each side — the corridor
    /// slack that bounds nudge offsets. `vertical:` flips the roles.
    func slack(coordinate: Int64, lo: Int64, hi: Int64,
               vertical: Bool) -> (before: Int64, after: Int64) {
        var gapBefore = Int64.max / 4
        var gapAfter = Int64.max / 4
        for rect in rects {
            let (spanLo, spanHi, sideLo, sideHi) = vertical
                ? (rect.minY, rect.maxY, rect.minX, rect.maxX)
                : (rect.minX, rect.maxX, rect.minY, rect.maxY)
            guard lo < spanHi && hi > spanLo else { continue }
            if sideHi <= coordinate { gapBefore = min(gapBefore, coordinate - sideHi) }
            if sideLo >= coordinate { gapAfter = min(gapAfter, sideLo - coordinate) }
        }
        return (gapBefore, gapAfter)
    }

    private func binarySearch(_ array: [Int64], _ value: Int64) -> Int? {
        var lo = 0, hi = array.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if array[mid] == value { return mid }
            if array[mid] < value { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }
}

// MARK: - PathSearch — multi-source/multi-target A*

/// One search per edge over the shared field. Virtual super-source arcs are
/// the source stubs (seed cost = stub length, horizontal axis); virtual
/// super-target arcs are the target stubs (exit cost = stub length + a bend
/// when arriving vertically, correctly pricing the corner onto the
/// horizontal stub). State carries the arrival axis so bends are exact.
/// Determinism: binary heap ordered by (f, insertion counter); neighbors
/// expanded in fixed (x, y)-sorted order; all-integer costs.
enum PathSearch {

    private struct HeapEntry {
        let f: Int64
        let counter: Int32
        let state: Int32
    }

    /// States: nodeIndex * 2 + axis (0 = horizontal arrival, 1 = vertical).
    /// The virtual goal is state -1 handled out of band.
    static func route(sources: [DiagramEdgeRouter.Terminal],
                      targets: [DiagramEdgeRouter.Terminal],
                      field: RoutingField, bendPenaltyQ: Int64) -> [QPoint]? {
        let xCount = field.xs.count
        let yCount = field.ys.count
        let nodeCount = xCount * yCount
        guard nodeCount > 0 else { return nil }

        // Target termini by node index, array-scanned (≤ 2 entries).
        var goalNodes: [(node: Int, terminal: DiagramEdgeRouter.Terminal)] = []
        for terminal in targets {
            guard let xi = field.xIndex(of: terminal.terminus.x),
                  let yi = field.yIndex(of: terminal.terminus.y) else { continue }
            goalNodes.append((yi * xCount + xi, terminal))
        }
        guard !goalNodes.isEmpty else { return nil }

        var g = [Int64](repeating: .max, count: nodeCount * 2)
        var parent = [Int32](repeating: -2, count: nodeCount * 2) // -2 unvisited
        var heap: [HeapEntry] = []
        var counter: Int32 = 0

        func heuristic(_ node: Int) -> Int64 {
            let x = field.xs[node % xCount]
            let y = field.ys[node / xCount]
            var best = Int64.max
            for goal in goalNodes {
                let gx = field.xs[goal.node % xCount]
                let gy = field.ys[goal.node / xCount]
                best = min(best, abs(x - gx) + abs(y - gy))
            }
            return best
        }

        func push(state: Int, cost: Int64, from: Int32) {
            guard cost < g[state] else { return }
            g[state] = cost
            parent[state] = from
            heap.append(HeapEntry(f: cost + heuristic(state / 2), counter: counter,
                                  state: Int32(state)))
            counter += 1
            var i = heap.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if (heap[p].f, heap[p].counter) <= (heap[i].f, heap[i].counter) { break }
                heap.swapAt(p, i); i = p
            }
        }

        func pop() -> HeapEntry? {
            guard let first = heap.first else { return nil }
            heap[0] = heap[heap.count - 1]
            heap.removeLast()
            var i = 0
            while true {
                let l = 2 * i + 1, r = 2 * i + 2
                var smallest = i
                if l < heap.count,
                   (heap[l].f, heap[l].counter) < (heap[smallest].f, heap[smallest].counter) {
                    smallest = l
                }
                if r < heap.count,
                   (heap[r].f, heap[r].counter) < (heap[smallest].f, heap[smallest].counter) {
                    smallest = r
                }
                if smallest == i { break }
                heap.swapAt(i, smallest); i = smallest
            }
            return first
        }

        // Seed: parent encodes -(sourceIndex) - 10 so reconstruction can
        // recover which source terminal won.
        for (index, terminal) in sources.enumerated() {
            guard let xi = field.xIndex(of: terminal.terminus.x),
                  let yi = field.yIndex(of: terminal.terminus.y) else { continue }
            let state = (yi * xCount + xi) * 2 + 0 // stubs are horizontal
            push(state: state, cost: terminal.stubLength, from: Int32(-index - 10))
        }
        guard !heap.isEmpty else { return nil }

        var bestGoal: (cost: Int64, state: Int, terminal: DiagramEdgeRouter.Terminal)?

        while let entry = pop() {
            let state = Int(entry.state)
            let cost = g[state]
            if entry.f > cost + heuristic(state / 2) { continue } // stale
            if let best = bestGoal, cost >= best.cost { break }

            let node = state / 2
            let axis = state % 2
            // Goal check: exiting through a target stub (horizontal) costs
            // its length plus a bend when we arrived vertically.
            for goal in goalNodes where goal.node == node {
                let exit = cost + goal.terminal.stubLength
                    + (axis == 1 ? bendPenaltyQ : 0)
                if bestGoal == nil || exit < bestGoal!.cost {
                    bestGoal = (exit, state, goal.terminal)
                }
            }

            let xi = node % xCount
            let yi = node / xCount
            // Fixed (x, y)-sorted expansion: left, up, down, right.
            if xi > 0, field.horizontalOpen(yi: yi, fromXi: xi - 1) {
                let length = field.xs[xi] - field.xs[xi - 1]
                let bend: Int64 = axis == 0 ? 0 : bendPenaltyQ
                push(state: (node - 1) * 2 + 0, cost: cost + length + bend,
                     from: Int32(state))
            }
            if yi > 0, field.verticalOpen(xi: xi, fromYi: yi - 1) {
                let length = field.ys[yi] - field.ys[yi - 1]
                let bend: Int64 = axis == 1 ? 0 : bendPenaltyQ
                push(state: (node - xCount) * 2 + 1, cost: cost + length + bend,
                     from: Int32(state))
            }
            if yi < yCount - 1, field.verticalOpen(xi: xi, fromYi: yi) {
                let length = field.ys[yi + 1] - field.ys[yi]
                let bend: Int64 = axis == 1 ? 0 : bendPenaltyQ
                push(state: (node + xCount) * 2 + 1, cost: cost + length + bend,
                     from: Int32(state))
            }
            if xi < xCount - 1, field.horizontalOpen(yi: yi, fromXi: xi) {
                let length = field.xs[xi + 1] - field.xs[xi]
                let bend: Int64 = axis == 0 ? 0 : bendPenaltyQ
                push(state: (node + 1) * 2 + 0, cost: cost + length + bend,
                     from: Int32(state))
            }
        }

        guard let goal = bestGoal else { return nil }

        var nodes: [QPoint] = []
        var cursor = Int32(goal.state)
        var sourceIndex = -1
        while cursor >= 0 {
            let node = Int(cursor) / 2
            nodes.append(QPoint(x: field.xs[node % xCount], y: field.ys[node / xCount]))
            let next = parent[Int(cursor)]
            if next <= -10 { sourceIndex = Int(-next - 10) }
            cursor = next
        }
        nodes.reverse()
        guard sourceIndex >= 0, sourceIndex < sources.count else { return nil }
        var path = [sources[sourceIndex].anchor]
        path.append(contentsOf: nodes)
        path.append(goal.terminal.anchor)
        return path
    }
}

// MARK: - TrackAllocator — deterministic corridor nudging

/// Edges sharing a corridor run get symmetric parallel offsets so they don't
/// overprint. A separate pure stage behind `route()`: interference groups by
/// (axis, coordinate, interval overlap); members ordered by (propertyRef,
/// fromElementUuid, segment index) — the full total order; offsets in
/// `spacingQ` steps, each clamped to half the corridor slack. Polyline
/// endpoints (anchors, stubs) never move — the two adjacent perpendicular
/// segments stretch to follow.
enum TrackAllocator {

    private struct SegmentRef {
        let pathIndex: Int
        let segIndex: Int
        let vertical: Bool
        let coordinate: Int64
        let lo: Int64
        let hi: Int64
        let orderKey: (String, String, Int)
    }

    static func nudge(_ paths: inout [[QPoint]?], edges: [DiagramEdgeRouter.EdgeRequest],
                      field: RoutingField, spacingQ: Int64) {
        var segments: [SegmentRef] = []
        for (pathIndex, path) in paths.enumerated() {
            guard let path, path.count >= 4 else { continue }
            // Interior segments only: exclude the first and last (they carry
            // the anchors and stub joins).
            for segIndex in 1...(path.count - 3) {
                let a = path[segIndex], b = path[segIndex + 1]
                if a == b { continue }
                let vertical = a.x == b.x
                segments.append(SegmentRef(
                    pathIndex: pathIndex, segIndex: segIndex, vertical: vertical,
                    coordinate: vertical ? a.x : a.y,
                    lo: vertical ? min(a.y, b.y) : min(a.x, b.x),
                    hi: vertical ? max(a.y, b.y) : max(a.x, b.x),
                    orderKey: (edges[pathIndex].propertyRef,
                               edges[pathIndex].fromElementUuid, segIndex)))
            }
        }

        // Bucket by (axis, coordinate) with a deterministic sort, then split
        // buckets into connected components by interval overlap.
        segments.sort {
            if $0.vertical != $1.vertical { return !$0.vertical }
            if $0.coordinate != $1.coordinate { return $0.coordinate < $1.coordinate }
            if $0.lo != $1.lo { return $0.lo < $1.lo }
            return $0.orderKey < $1.orderKey
        }

        var index = 0
        while index < segments.count {
            let head = segments[index]
            var group = [head]
            var reach = head.hi
            var next = index + 1
            while next < segments.count {
                let seg = segments[next]
                guard seg.vertical == head.vertical,
                      seg.coordinate == head.coordinate,
                      seg.lo <= reach else { break }
                reach = max(reach, seg.hi)
                group.append(seg)
                next += 1
            }
            index = next
            guard group.count > 1 else { continue }

            group.sort { $0.orderKey < $1.orderKey }
            let spanLo = group.map(\.lo).min()!
            let spanHi = group.map(\.hi).max()!
            // Track positions: `spacingQ` steps, ideally centered on the
            // run's current line, shifted (and compressed when needed) to
            // stay within half the corridor slack each side — a run hugging
            // an inflated ring shifts INTO the corridor instead of freezing.
            let gaps = field.slack(coordinate: head.coordinate, lo: spanLo,
                                   hi: spanHi, vertical: head.vertical)
            let lowBound = -gaps.before / 2
            let highBound = gaps.after / 2
            let count = Int64(group.count)
            let step = min(spacingQ, max((highBound - lowBound) / max(count - 1, 1), 0))
            let span = step * (count - 1)
            let base = max(lowBound, min(-span / 2, highBound - span))
            for (position, seg) in group.enumerated() {
                let offset = base + Int64(position) * step
                guard offset != 0, var path = paths[seg.pathIndex] else { continue }
                if seg.vertical {
                    path[seg.segIndex].x += offset
                    path[seg.segIndex + 1].x += offset
                } else {
                    path[seg.segIndex].y += offset
                    path[seg.segIndex + 1].y += offset
                }
                paths[seg.pathIndex] = path
            }
        }
    }
}
