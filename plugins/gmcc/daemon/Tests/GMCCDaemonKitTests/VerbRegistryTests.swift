import XCTest

@testable import GMCCDaemonKit

/// The verb CATALOGUE's coverage test — the CheatsheetTests precedent applied
/// to the registry: a new MessageType with no row FAILS THE BUILD.
///
/// There is nothing here about authorization. This is a single-user local dev
/// harness; the registry classifies verbs (read vs write, which pen tool covers
/// them) and refuses nobody.
final class VerbRegistryTests: XCTestCase {

    // MARK: - Coverage

    func testEveryMessageTypeHasARegistryRow() {
        for type in MessageType.allCases {
            if VerbRegistry.unroledMessageTypes.contains(type) { continue }
            XCTAssertNotNil(
                VerbRegistry.spec(for: type),
                """
                MessageType.\(type) (\(type.rawValue)) has no VerbSpec. Every verb \
                needs a catalogue row: add one to VerbRegistry.all, or — only for a \
                daemon→client-only message — to unroledMessageTypes.
                """)
        }
    }

    func testRegistryHasNoDuplicateRows() {
        let types = VerbRegistry.all.map(\.messageType)
        XCTAssertEqual(types.count, Set(types).count, "VerbRegistry.all repeats a MessageType")
        let penTools = VerbRegistry.all.compactMap(\.penTool)
        XCTAssertEqual(penTools.count, Set(penTools).count, "two verbs claim the same pen tool")

        // TWO ROWS CLAIMING ONE SPELLING IS A SILENT LAST-WINS: `byInvocation`
        // keeps whichever row is declared later, so the catalogue would answer
        // with the wrong MessageType for that spelling.
        let invocations = VerbRegistry.all.flatMap(\.gmInvocations)
        let duplicated = Set(invocations.filter { i in invocations.filter { $0 == i }.count > 1 })
        XCTAssertTrue(
            duplicated.isEmpty,
            "these invocation spellings are claimed by more than one VerbSpec: \(duplicated.sorted())")
        for composite in VerbRegistry.compositePenTools.keys {
            XCTAssertFalse(
                penTools.contains(composite),
                "\(composite) is declared BOTH as a composite and as a verb's penTool")
        }
    }

    func testUnroledMessageTypesAreDaemonToClientOnly() {
        // Widening this set is how the coverage test gets defeated — pin it.
        XCTAssertEqual(VerbRegistry.unroledMessageTypes, [.event, .error])
    }

    // MARK: - Methodology (guidance, never a gate)

    /// The four tools that advance the machine are the primary's BY
    /// METHODOLOGY, and the sheet names them. Nothing refuses a caller for
    /// using one — but each must exist as a pen tool, or the sheet points at a
    /// name nobody can call.
    func testPrimaryPenToolsAreServedByTheRegistry() {
        XCTAssertEqual(
            VerbRegistry.primaryPenTools,
            ["prompt_set_status", "arch_decide", "review_rank", "care_package_complete"])
        for tool in VerbRegistry.primaryPenTools {
            XCTAssertTrue(
                VerbRegistry.penToolNames.contains(tool),
                "\(tool) is named as the primary's call but no VerbSpec serves it")
        }
    }

    // MARK: - The catalogue reader

    func testVerbLedgerRendersTheCatalogue() throws {
        let data = try WireCodec.prettyEncoder.encode(VerbLedger.build())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let verbs = try XCTUnwrap(json["verbs"] as? [[String: Any]])
        XCTAssertFalse(verbs.isEmpty, "gmcc_hook verbs must list the MessageTypes it serves")
        XCTAssertTrue(
            verbs.allSatisfy { ($0["message_type"] as? String)?.isEmpty == false },
            "every catalogue row must name its MessageType — that is what the reader is for")
        XCTAssertNotNil(json["pen_replacements"])
        XCTAssertNil(json["would_refuse"], "the would-refuse ledger is gone; nothing may resurrect it")
        XCTAssertNil(json["enforcement"], "there is no enforcement mode any more")
    }
}
