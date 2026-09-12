import XCTest

@testable import GMCCDaemonKit

/// Resolution precedence, and the ambiguity that must never become a guess.
/// A wrong answer here files a whole session's work against the wrong prompt,
/// and the db is append-only — so the failure is permanent and silent, which is
/// exactly the pair that earns a test.
final class PromptResolverTests: XCTestCase {

    private func stub(seq: Int64, code: String, name: String) -> PromptStub {
        PromptStub(
            uuid: "uuid-\(seq)",
            sessionUuid: "session",
            seq: seq,
            code: code,
            name: name,
            status: "draft",
            version: 0,
            ckfsRelativeStoragePath: "path/\(seq)",
            reports: nil,
            createdAt: "2026-09-12T00:00:00Z",
            updatedAt: "2026-09-12T00:00:00Z")
    }

    private var corpus: [PromptStub] {
        [
            stub(seq: 1, code: "p1", name: "moving_data_models"),
            stub(seq: 9, code: "p9", name: "session_bound_hook_attribution"),
            stub(seq: 10, code: "p10", name: "fast_startup_immediate_briefing"),
            stub(seq: 11, code: "p11", name: "fast_startup_followup"),
        ]
    }

    private func matched(_ r: PromptResolver.Resolution) -> (PromptStub, PromptResolver.MatchKind)? {
        if case let .matched(stub, by) = r { return (stub, by) }
        return nil
    }

    func testBareIntegerResolvesBySeq() {
        let hit = matched(PromptResolver.resolve("10", in: corpus))
        XCTAssertEqual(hit?.0.uuid, "uuid-10")
        XCTAssertEqual(hit?.1, .seq)
    }

    func testCodeResolves() {
        let hit = matched(PromptResolver.resolve("p9", in: corpus))
        XCTAssertEqual(hit?.0.uuid, "uuid-9")
        XCTAssertEqual(hit?.1, .code)
    }

    func testCodeIsCaseInsensitive() {
        XCTAssertEqual(matched(PromptResolver.resolve("P9", in: corpus))?.0.uuid, "uuid-9")
    }

    func testExactNameResolves() {
        let hit = matched(PromptResolver.resolve("fast_startup_immediate_briefing", in: corpus))
        XCTAssertEqual(hit?.0.uuid, "uuid-10")
        XCTAssertEqual(hit?.1, .name)
    }

    /// The precedence case that matters: "fast_startup_followup" is an exact
    /// name AND a substring of nothing else, while the bare substring
    /// "fast_startup" hits two. An exact name must win outright rather than
    /// being dragged into the ambiguous tier by its neighbour.
    func testExactNameBeatsSubstringNeighbour() {
        let hit = matched(PromptResolver.resolve("fast_startup_followup", in: corpus))
        XCTAssertEqual(hit?.0.uuid, "uuid-11")
        XCTAssertEqual(hit?.1, .name)
    }

    func testUniqueSubstringResolves() {
        let hit = matched(PromptResolver.resolve("bound_hook", in: corpus))
        XCTAssertEqual(hit?.0.uuid, "uuid-9")
        XCTAssertEqual(hit?.1, .nameSubstring)
    }

    func testAmbiguousSubstringReturnsEveryCandidateInSeqOrder() {
        guard case let .ambiguous(hits) = PromptResolver.resolve("fast_startup", in: corpus) else {
            return XCTFail("expected ambiguous, got a single answer — a guess here files work against the wrong prompt")
        }
        XCTAssertEqual(hits.map(\.uuid), ["uuid-10", "uuid-11"])
    }

    func testUnknownSelectorIsNotFound() {
        guard case .notFound = PromptResolver.resolve("no_such_prompt", in: corpus) else {
            return XCTFail("expected notFound")
        }
    }

    /// A seq that does not exist must NOT fall through to a substring match on
    /// the digits — "99" is not a fuzzy search for a prompt named "...99...".
    func testUnknownSeqDoesNotFallThroughToSubstring() {
        guard case .notFound = PromptResolver.resolve("99", in: corpus) else {
            return XCTFail("a missing seq must be notFound, never a fuzzy hit")
        }
    }

    func testEmptySelectorIsNotFound() {
        guard case .notFound = PromptResolver.resolve("   ", in: corpus) else {
            return XCTFail("expected notFound")
        }
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(matched(PromptResolver.resolve("  10  ", in: corpus))?.0.uuid, "uuid-10")
    }
}
