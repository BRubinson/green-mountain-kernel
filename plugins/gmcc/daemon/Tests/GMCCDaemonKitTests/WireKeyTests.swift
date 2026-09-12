import XCTest
@testable import GMCCDaemonKit

/// Wire-contract regression tests. The exhaustive wire-key contract lives in
/// Fixtures/wire_keys.golden, regenerated and diffed by scripts/wire_keys.py
/// (static walk — no instantiation). These tests cover what a static walk
/// cannot: the two mixed-key survivor types actually decoding correctly under
/// the coder strategies, which is where retained explicit CodingKeys silently
/// nil out sibling Optional fields if the sibling keys are not deleted.
final class WireKeyTests: XCTestCase {

    func testErrorPayloadRoundTripsDaemonProtocolVersion() throws {
        let payload = ErrorPayload(
            code: .protocolMismatch,
            message: "stale daemon",
            daemonProtocolVersion: 6
        )
        let data = try NDJSON.encodeLine(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["code"] as? String, "PROTOCOL_MISMATCH")
        XCTAssertEqual(json["daemon_protocol_version"] as? Int, 6)

        let decoded = try NDJSON.decode(ErrorPayload.self, from: data)
        XCTAssertEqual(decoded.code, .protocolMismatch)
        // The directional-retry landmine: this is nil if ErrorPayload keeps an
        // explicit CodingKeys entry for daemonProtocolVersion alongside codeRaw.
        XCTAssertEqual(decoded.daemonProtocolVersion, 6)
    }

    func testRawEnvelopeHeadRoundTrips() throws {
        let head = RawEnvelopeHead(protocolVersion: 6, typeRaw: "PING", requestId: "r-1")
        let data = try NDJSON.encodeLine(head)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "PING")
        XCTAssertEqual(json["protocol_version"] as? Int, 6)
        XCTAssertEqual(json["request_id"] as? String, "r-1")

        let decoded = try NDJSON.decode(RawEnvelopeHead.self, from: data)
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertEqual(decoded.protocolVersion, 6)
        XCTAssertEqual(decoded.requestId, "r-1")
    }

    // MARK: - caller_role is GONE from the wire

    /// The role tag was authorization machinery, and this harness authorizes
    /// nothing. A request must carry NO caller_role key, and the head must
    /// decode without one — a stale peer that still stamps the key is simply
    /// ignored rather than rejected.
    func testRequestsCarryNoCallerRoleKey() throws {
        let request = RequestEnvelope(
            type: .reviewRank, requestId: "r-2", payload: EmptyPayload())
        let data = try NDJSON.encodeLine(request)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["caller_role"], "the role tag is removed from the wire")
        XCTAssertEqual(json["type"] as? String, "REVIEW_RANK")
    }

    /// A stale peer stamping `caller_role` must not break the decode — the
    /// key is unknown data now, and unknown keys have always been ignored.
    func testStaleCallerRoleKeyIsIgnoredNotRejected() throws {
        let line = Data(
            #"{"protocol_version":\#(GMCCWireProtocol.version),"type":"PING","request_id":"r-4","caller_role":"agent"}"#
                .utf8)
        let head = try NDJSON.decode(RawEnvelopeHead.self, from: line)
        XCTAssertEqual(head.type, .ping, "the head must still decode")
        XCTAssertEqual(head.requestId, "r-4")
    }

    func testHighTrafficRowRoundTrips() throws {
        let stub = PromptStub(
            uuid: "u-1", sessionUuid: "s-1", seq: 3, code: "p3",
            name: "demo", status: "draft", version: 2,
            ckfsRelativeStoragePath: "projects/r/prompts/3_demo",
            createdAt: "2026-08-22T00:00:00Z", updatedAt: "2026-08-22T00:00:00Z")
        let data = try NDJSON.encodeLine(stub)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["session_uuid"] as? String, "s-1")
        let decoded = try NDJSON.decode(PromptStub.self, from: data)
        XCTAssertEqual(decoded, stub)
    }
}
