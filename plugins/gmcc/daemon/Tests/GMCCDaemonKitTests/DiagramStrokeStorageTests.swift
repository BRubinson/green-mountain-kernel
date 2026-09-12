import XCTest
@testable import GMCCDaemonKit

/// Packed stroke storage: the wire-format guarantees, RDP decimation, and
/// the quantization contract that keeps the reducer↔daemon parity oracle
/// honest.
final class DiagramStrokeStorageTests: XCTestCase {

    // MARK: - Packing

    /// The layout is a FORMAT, not a memory dump: this blob outlives the
    /// machine that wrote it, so endianness and width are pinned by a golden
    /// byte assertion rather than by whatever the compiler felt like.
    func testPackedLayoutIsLittleEndianNineBytesPerVertex() {
        let packed = DiagramStrokeCodec.pack([DiagramVertex(x: 1, y: -2, pressure: 1)])
        XCTAssertEqual(packed.count, DiagramStrokeCodec.bytesPerVertex)
        XCTAssertEqual(packed.count, 9)
        // 1.0f = 0x3F800000, little-endian on the wire.
        XCTAssertEqual([UInt8](packed)[0...3], [0x00, 0x00, 0x80, 0x3F])
        // -2.0f = 0xC0000000.
        XCTAssertEqual([UInt8](packed)[4...7], [0x00, 0x00, 0x00, 0xC0])
        // pressure 1.0 -> 254 (255 is reserved as the nil sentinel).
        XCTAssertEqual([UInt8](packed)[8], 254)
    }

    func testPackRoundTripsIncludingNilPressure() throws {
        let vertices = [
            DiagramVertex(x: 0, y: 0, pressure: 0),
            DiagramVertex(x: 12.5, y: -8.25),
            DiagramVertex(x: -3.75, y: 400.5, pressure: 1),
            DiagramVertex(x: 1, y: 1, pressure: 0.5),
        ]
        let normalized = DiagramStrokeCodec.normalizedForStorage(vertices)
        let unpacked = try DiagramStrokeCodec.unpack(
            DiagramStrokeCodec.pack(normalized), count: normalized.count)
        XCTAssertEqual(unpacked, normalized)
        // A nil pressure must survive as nil, NOT as 0 — "no stylus" and
        // "feather-light" are different facts and a trackpad reports the
        // first one constantly.
        XCTAssertNil(unpacked[1].pressure)
        XCTAssertEqual(unpacked[0].pressure, 0)
    }

    func testUnpackRejectsATruncatedBlob() {
        let packed = DiagramStrokeCodec.pack([
            DiagramVertex(x: 1, y: 1), DiagramVertex(x: 2, y: 2)])
        XCTAssertThrowsError(try DiagramStrokeCodec.unpack(packed, count: 3)) {
            guard case StoreError.corruptState = $0 else {
                return XCTFail("expected corruptState, got \($0)")
            }
        }
        XCTAssertThrowsError(try DiagramStrokeCodec.unpack(packed.dropLast(), count: 2))
    }

    func testEmptyStrokePacksToEmptyData() throws {
        XCTAssertEqual(DiagramStrokeCodec.pack([]).count, 0)
        XCTAssertEqual(try DiagramStrokeCodec.unpack(Data(), count: 0), [])
    }

    // MARK: - Quantization (the parity contract)

    /// THE reason `normalizedForStorage` exists.
    ///
    /// The differential oracle compares payloads by `String(describing:)` —
    /// exact equality. The daemon stores f32/u8 and reads back changed bits;
    /// the reducer keeps exact Doubles in memory. Without a shared
    /// quantization the two would "disagree" about a stroke neither of them
    /// got wrong. Normalizing is idempotent, which is what makes it safe to
    /// apply on every write.
    func testNormalizationIsIdempotentAndSurvivesTheRoundTrip() throws {
        let raw = DiagramVertex(x: 0.1, y: 1234.5678, pressure: 0.4)
        let once = DiagramStrokeCodec.normalizedForStorage(raw)
        let twice = DiagramStrokeCodec.normalizedForStorage(once)
        XCTAssertEqual(once, twice, "normalization must be idempotent")

        let unpacked = try DiagramStrokeCodec.unpack(
            DiagramStrokeCodec.pack([once]), count: 1)
        XCTAssertEqual(unpacked[0], once,
                       "a normalized vertex must survive storage bit-exactly")
    }

    /// Pressure is lossy BY DESIGN — u8, 254 steps — because that is the
    /// format the prompt specified. Pinned so nobody "fixes" it later
    /// without noticing the storage cost changed.
    func testPressureQuantizesOnto254Steps() {
        let normalized = DiagramStrokeCodec.normalizedForStorage(
            DiagramVertex(x: 0, y: 0, pressure: 0.4))
        XCTAssertEqual(normalized.pressure ?? 0, 102.0 / 254.0, accuracy: 1e-12)
        // Clamping, not wrapping, at both ends.
        XCTAssertEqual(
            DiagramStrokeCodec.normalizedForStorage(
                DiagramVertex(x: 0, y: 0, pressure: 5)).pressure, 1)
        XCTAssertEqual(
            DiagramStrokeCodec.normalizedForStorage(
                DiagramVertex(x: 0, y: 0, pressure: -3)).pressure, 0)
    }

    func testNormalizationOnlyTouchesStrokes() {
        // Shape vertices persist as REAL rows and round-trip exactly, so
        // quantizing them would assert a precision loss that never happens.
        let shape = DiagramElementPayload.drawingShape(DrawingShapePayload(
            shapeKind: .rectangle,
            vertices: [DiagramVertex(x: 0.1, y: 0.2, pressure: 0.4)]))
        XCTAssertEqual(DiagramStrokeCodec.normalizedForStorage(shape), shape)
    }

    // MARK: - Decimation

    func testRdpKeepsEndpointsAndCollapsesCollinearRuns() {
        // 11 points along a straight line: everything between the endpoints
        // is redundant.
        let straight = (0...10).map { DiagramVertex(x: Double($0), y: 0) }
        let decimated = DiagramStrokeCodec.decimate(straight)
        XCTAssertEqual(decimated.count, 2)
        XCTAssertEqual(decimated.first, straight.first)
        XCTAssertEqual(decimated.last, straight.last)
    }

    func testRdpPreservesGenuineCorners() {
        let corner = [
            DiagramVertex(x: 0, y: 0),
            DiagramVertex(x: 5, y: 0),
            DiagramVertex(x: 10, y: 0),
            DiagramVertex(x: 10, y: 50),   // a real corner
            DiagramVertex(x: 10, y: 100),
        ]
        let decimated = DiagramStrokeCodec.decimate(corner)
        XCTAssertTrue(decimated.contains(DiagramVertex(x: 10, y: 0)),
                      "a 90-degree turn must survive decimation")
        XCTAssertEqual(decimated.count, 3)
    }

    /// The prompt's own claim, pinned: a ~100-vertex trackpad stroke keeps
    /// roughly a quarter of its points with no visible change.
    func testTrackpadScaleStrokeDecimatesSubstantially() {
        // A gentle arc sampled far more finely than the curve needs.
        let arc = (0..<100).map { index -> DiagramVertex in
            let t = Double(index) / 99
            return DiagramVertex(x: t * 300, y: sin(t * .pi) * 40)
        }
        let decimated = DiagramStrokeCodec.decimate(arc)
        XCTAssertLessThan(decimated.count, 40,
                          "0.75px RDP should shed most of a finely sampled arc")
        XCTAssertGreaterThan(decimated.count, 2)
        XCTAssertEqual(decimated.first, arc.first)
        XCTAssertEqual(decimated.last, arc.last)
        // Every kept point is still one of the ORIGINAL samples — RDP
        // selects, it never invents.
        for vertex in decimated { XCTAssertTrue(arc.contains(vertex)) }
    }

    func testDecimationLeavesShortStrokesAlone() {
        let two = [DiagramVertex(x: 0, y: 0), DiagramVertex(x: 1, y: 1)]
        XCTAssertEqual(DiagramStrokeCodec.decimate(two), two)
        XCTAssertEqual(DiagramStrokeCodec.decimate([]), [])
    }

    // MARK: - The registry axis that picks the representation

    func testStorageStrategyIsDeclaredOnTheRegistry() {
        // Strokes pack; low-cardinality shapes keep queryable vertex rows.
        guard case .packedBlob(let column, let countColumn, let fallback) =
                DiagramElementTypeSpec.spec(for: .drawingStroke).vertexStorage else {
            return XCTFail("strokes must declare packed storage")
        }
        XCTAssertEqual(column, "packed_vertices")
        XCTAssertEqual(countColumn, "vertex_count")
        XCTAssertEqual(fallback.table, "diagram_stroke_vertex")

        guard case .rows(let table, _) =
                DiagramElementTypeSpec.spec(for: .drawingShape).vertexStorage else {
            return XCTFail("shapes must keep vertex rows")
        }
        XCTAssertEqual(table, "diagram_shape_vertex")

        // Text is sized explicitly and has no geometry rows at all.
        XCTAssertEqual(DiagramElementTypeSpec.spec(for: .drawingText).vertexStorage, .none)
        XCTAssertNil(DiagramElementTypeSpec.spec(for: .drawingText).vertexTable)
    }
}
