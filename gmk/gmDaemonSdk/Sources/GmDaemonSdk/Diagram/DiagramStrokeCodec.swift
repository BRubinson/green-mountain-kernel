import Foundation

/// Freehand stroke geometry: decimation, and the packed on-disk form.
///
/// Kit-resident, not app-resident, for the same reason `DiagramTreeReducer`
/// is: GMVibes decimates a stroke locally the moment the pen lifts, and the
/// daemon stores it. If the two used different arithmetic the same gesture
/// would round-trip to something else, and the parity oracle would be the
/// thing that noticed — loudly, and much later.
///
/// ## What is stored
///
/// The INPUT CENTERLINE, never the rendered outline: `[x, y, pressure?]` per
/// vertex, element-local. The fat, tapered stroke is derived at render time.
/// Storing the outline would bake today's brush into the data and make a
/// width change a migration.
///
/// ## Why packed
///
/// A vertex row is a full BaseEntity — uuid, version, two timestamps, a seq,
/// an FK — roughly 250 bytes of scaffolding around 24 bytes of coordinate. A
/// single trackpad stroke can be hundreds of points. Shapes, which have four
/// vertices and benefit from being queryable, keep their rows; strokes pack.
/// `DiagramElementTypeSpec.vertexStorage` is what decides, per type.
public enum DiagramStrokeCodec {

    /// RDP tolerance in element-local units. ~0.75px keeps a 100-vertex
    /// trackpad stroke at roughly 25 with no visible change.
    public static let defaultEpsilon: Double = 0.75

    /// 4-byte float x, 4-byte float y, 1-byte pressure.
    public static let bytesPerVertex = 9

    /// Pressure sentinel for "this device reported none" — distinct from a
    /// genuine zero, which is a real (feather-light) reading.
    static let nilPressure: UInt8 = 255
    /// Real pressures quantize onto 0...254 so 255 stays free as the
    /// sentinel.
    static let pressureScale: Double = 254

    // MARK: - Quantization

    /// Round-trip a vertex through the STORAGE precision without touching
    /// the database.
    ///
    /// This exists because of the parity oracle. `DiagramTreeReducer` keeps
    /// vertices as exact `Double`s in memory; the daemon writes them as
    /// f32/u8 and reads them back changed in the last bits. The oracle
    /// compares payloads by `String(describing:)` — exact equality — so
    /// without this the two implementations would "disagree" about a stroke
    /// neither of them got wrong.
    ///
    /// Both write paths normalize through here, so the in-memory tree and
    /// the persisted tree hold the same numbers by construction rather than
    /// by tolerance.
    public static func normalizedForStorage(_ vertex: DiagramVertex) -> DiagramVertex {
        DiagramVertex(
            x: Double(Float(vertex.x)),
            y: Double(Float(vertex.y)),
            pressure: vertex.pressure.map { quantizedPressure($0) })
    }

    public static func normalizedForStorage(_ vertices: [DiagramVertex]) -> [DiagramVertex] {
        vertices.map(normalizedForStorage)
    }

    /// Normalize a payload to exactly what storage will hold.
    ///
    /// Called by BOTH write paths — the daemon's and the reducer's — so an
    /// in-memory tree and a persisted tree agree by construction. Only
    /// strokes are affected: shape vertices are stored as REAL rows and
    /// round-trip exactly, so quantizing them would be a lie about
    /// precision that does not exist.
    public static func normalizedForStorage(
        _ payload: DiagramElementPayload
    ) -> DiagramElementPayload {
        guard case .drawingStroke(let stroke) = payload else { return payload }
        return .drawingStroke(DrawingStrokePayload(
            tool: stroke.tool, strokeColor: stroke.strokeColor,
            strokeWidth: stroke.strokeWidth,
            vertices: normalizedForStorage(stroke.vertices)))
    }

    static func quantizedPressure(_ p: Double) -> Double {
        let clamped = min(max(p, 0), 1)
        return (clamped * pressureScale).rounded() / pressureScale
    }

    // MARK: - Packing

    /// Little-endian, explicitly: this blob outlives the machine that wrote
    /// it, and "native order" is not a format.
    public static func pack(_ vertices: [DiagramVertex]) -> Data {
        var data = Data(capacity: vertices.count * bytesPerVertex)
        for vertex in vertices {
            withUnsafeBytes(of: Float(vertex.x).bitPattern.littleEndian) {
                data.append(contentsOf: $0)
            }
            withUnsafeBytes(of: Float(vertex.y).bitPattern.littleEndian) {
                data.append(contentsOf: $0)
            }
            if let pressure = vertex.pressure {
                let clamped = min(max(pressure, 0), 1)
                data.append(UInt8((clamped * pressureScale).rounded()))
            } else {
                data.append(nilPressure)
            }
        }
        return data
    }

    public static func unpack(_ data: Data, count: Int) throws -> [DiagramVertex] {
        guard count >= 0 else {
            throw StoreError.corruptState(
                entity: "diagram_drawing_stroke",
                detail: "negative packed vertex_count \(count)")
        }
        let expected = count * bytesPerVertex
        guard data.count == expected else {
            throw StoreError.corruptState(
                entity: "diagram_drawing_stroke",
                detail: "packed stroke is \(data.count) bytes, expected \(expected) "
                      + "for \(count) vertices")
        }
        let bytes = [UInt8](data)
        var vertices: [DiagramVertex] = []
        vertices.reserveCapacity(count)
        for index in 0..<count {
            let base = index * bytesPerVertex
            let xBits = UInt32(bytes[base])
                | UInt32(bytes[base + 1]) << 8
                | UInt32(bytes[base + 2]) << 16
                | UInt32(bytes[base + 3]) << 24
            let yBits = UInt32(bytes[base + 4])
                | UInt32(bytes[base + 5]) << 8
                | UInt32(bytes[base + 6]) << 16
                | UInt32(bytes[base + 7]) << 24
            let raw = bytes[base + 8]
            vertices.append(DiagramVertex(
                x: Double(Float(bitPattern: xBits)),
                y: Double(Float(bitPattern: yBits)),
                pressure: raw == nilPressure ? nil : Double(raw) / pressureScale))
        }
        return vertices
    }

    // MARK: - Decimation

    /// Ramer–Douglas–Peucker, run once on pointer-up.
    ///
    /// A trackpad emits far more points than the curve needs; keeping them
    /// all costs storage and slows every later render for no visual gain.
    /// Endpoints are always preserved, so a decimated stroke still starts
    /// and ends exactly where the hand did.
    public static func decimate(
        _ vertices: [DiagramVertex], epsilon: Double = defaultEpsilon
    ) -> [DiagramVertex] {
        guard vertices.count > 2, epsilon > 0 else { return vertices }
        var keep = [Bool](repeating: false, count: vertices.count)
        keep[0] = true
        keep[vertices.count - 1] = true
        simplify(vertices, 0, vertices.count - 1, epsilon, &keep)
        return zip(vertices, keep).compactMap { $1 ? $0 : nil }
    }

    private static func simplify(
        _ v: [DiagramVertex], _ first: Int, _ last: Int,
        _ epsilon: Double, _ keep: inout [Bool]
    ) {
        guard last > first + 1 else { return }
        var maxDistance = 0.0
        var maxIndex = first
        for index in (first + 1)..<last {
            let distance = perpendicularDistance(v[index], v[first], v[last])
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = index
            }
        }
        guard maxDistance > epsilon else { return }
        keep[maxIndex] = true
        simplify(v, first, maxIndex, epsilon, &keep)
        simplify(v, maxIndex, last, epsilon, &keep)
    }

    private static func perpendicularDistance(
        _ p: DiagramVertex, _ a: DiagramVertex, _ b: DiagramVertex
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
        }
        let area = abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x)
        return area / lengthSquared.squareRoot()
    }
}
