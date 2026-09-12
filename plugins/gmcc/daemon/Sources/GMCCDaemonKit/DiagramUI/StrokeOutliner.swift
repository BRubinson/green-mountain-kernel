import CoreGraphics
import Foundation

/// Pressure-aware freehand outlining — a compact Swift port of the
/// perfect-freehand algorithm (Steve Ruiz, MIT — ported from upstream
/// source; the vendored excalidraw tree carries it only as an npm
/// dependency, so the math lives here).
///
/// PURE and SwiftUI-free: centerline+pressure in, closed outline polygon
/// out. Derivation happens at RESOLVE time over the persisted vertices —
/// the codec stored centerline+pressure for exactly this, so no migration
/// and no wire change is involved; bumping renderAlgoVersion is the only
/// contract (the fingerprint's representative of render code).
public enum StrokeOutliner {

    public struct Options {
        /// Full stroke diameter at pressure 1.
        public var size: Double
        /// 0 = constant width, 1 = full pressure thinning.
        public var thinning: Double
        /// Input smoothing (streamline): 0 = raw points, 1 = heavy lag.
        public var streamline: Double
        /// Derive pressure from velocity when the input carries none.
        public var simulatePressure: Bool

        public init(size: Double, thinning: Double = 0.6,
                    streamline: Double = 0.35, simulatePressure: Bool = true) {
            self.size = size
            self.thinning = thinning
            self.streamline = streamline
            self.simulatePressure = simulatePressure
        }
    }

    /// The closed outline polygon (left side then reversed right side, with
    /// round caps). Returns [] for degenerate input (< 2 distinct points) —
    /// callers fall back to the plain stroked centerline.
    public static func outline(points: [CGPoint], pressures: [Double?],
                               options: Options) -> [CGPoint] {
        guard points.count >= 2, options.size > 0 else { return [] }

        // 1. Streamline: exponential moving average toward each raw point.
        //    (perfect-freehand's t = 0.15 + (1 - streamline) * 0.85.)
        let t = 0.15 + (1 - min(max(options.streamline, 0), 1)) * 0.85
        var smoothed: [CGPoint] = [points[0]]
        for point in points.dropFirst() {
            let previous = smoothed[smoothed.count - 1]
            let next = CGPoint(x: previous.x + (point.x - previous.x) * t,
                               y: previous.y + (point.y - previous.y) * t)
            if hypot(next.x - previous.x, next.y - previous.y) > 0.01 {
                smoothed.append(next)
            }
        }
        guard smoothed.count >= 2 else { return [] }

        // 2. Per-point pressure: carried, or simulated from segment length
        //    (fast movement = low pressure, the perfect-freehand heuristic).
        var pressure = [Double](repeating: 0.5, count: smoothed.count)
        if options.simulatePressure {
            var running = 0.5
            for index in 1..<smoothed.count {
                let distance = hypot(smoothed[index].x - smoothed[index - 1].x,
                                     smoothed[index].y - smoothed[index - 1].y)
                let speed = min(1, distance / options.size)
                running = min(1, max(0.1, running + ((1 - speed) - running) * 0.275))
                pressure[index] = running
            }
            pressure[0] = pressure.count > 1 ? pressure[1] : 0.5
        }
        // Real pressure (when the stroke recorded it) wins over simulation.
        let carried = pressures.prefix(points.count)
        if carried.contains(where: { $0 != nil }) {
            // Index against the RAW points; nearest smoothed index is fine
            // at streamline scale — both arrays are monotonic in arclength.
            for index in 0..<smoothed.count {
                let rawIndex = min(index, carried.count - 1)
                if rawIndex >= 0, let real = carried[rawIndex] {
                    pressure[index] = min(1, max(0, real))
                }
            }
        }

        // 3. Radii: thinning interpolates between 25% and 100% of size/2.
        func radius(_ pressureValue: Double) -> Double {
            let thinning = min(max(options.thinning, 0), 1)
            let scaled = 0.25 + pressureValue * 0.75
            return max(0.5, options.size / 2 * (1 - thinning * (1 - scaled)))
        }

        // 4. Perpendicular offsets → left/right rails.
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in 0..<smoothed.count {
            let ahead = smoothed[min(index + 1, smoothed.count - 1)]
            let behind = smoothed[max(index - 1, 0)]
            var dx = ahead.x - behind.x
            var dy = ahead.y - behind.y
            let length = hypot(dx, dy)
            guard length > 0.0001 else { continue }
            dx /= length
            dy /= length
            let r = CGFloat(radius(pressure[index]))
            let point = smoothed[index]
            left.append(CGPoint(x: point.x + dy * r, y: point.y - dx * r))
            right.append(CGPoint(x: point.x - dy * r, y: point.y + dx * r))
        }
        guard left.count >= 2 else { return [] }

        // 5. Round end caps: a small fan around each endpoint.
        func cap(center: CGPoint, from start: CGPoint, to end: CGPoint) -> [CGPoint] {
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            var endAngle = atan2(end.y - center.y, end.x - center.x)
            let r = hypot(start.x - center.x, start.y - center.y)
            guard r > 0.1 else { return [] }
            while endAngle < startAngle { endAngle += 2 * .pi }
            let steps = 8
            return (1..<steps).map { step in
                let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
                return CGPoint(x: center.x + cos(angle) * r,
                               y: center.y + sin(angle) * r)
            }
        }
        let startCap = cap(center: smoothed[0], from: right[0], to: left[0])
        let endCap = cap(center: smoothed[smoothed.count - 1],
                         from: left[left.count - 1], to: right[right.count - 1])

        return left + endCap + right.reversed() + startCap
    }
}
