import XCTest

@testable import GmAgententicsSdk

// The roster contract.
//
// This is `VerbRegistryTests`' guarantee applied to the agent-tool surface:
// declaring a tool and forgetting to file it in the namespace should FAIL THE
// BUILD, not sit in the module unnoticed until someone wonders why the model
// never calls it.
//
// Every assertion here is about the SURFACE, not about behaviour. None of these
// tools is wired yet, so there is nothing to exercise — what can go wrong at
// this stage is structural: a duplicate name, a missing description, a tool
// filed under the wrong family, a family with nothing in it.
@available(GmAgentOs 1.0, *)
final class GmAgentToolRosterTests: XCTestCase {

    /// Every tool reachable from the namespace is reachable from `all`, and the
    /// per-family lists partition it exactly.
    ///
    /// Swift has no runtime conformance enumeration, so "every conformance in
    /// the module" cannot be asserted directly. What IS asserted is that the two
    /// routes into the surface — `GmAgentTools.all` and the per-family lists —
    /// agree. A tool added to a family list but not to `all` (or the reverse)
    /// fails here, which is the mistake actually likely when a tool is added.
    func testFamilyListsPartitionTheRoster() {
        let fromFamilies = GmAgentToolFamily.allCases
            .flatMap { GmAgentTools.tools(in: $0) }
            .map(\.name)
            .sorted()
        let fromAll = GmAgentTools.all.map(\.name).sorted()

        XCTAssertEqual(
            fromFamilies, fromAll,
            "GmAgentTools.all and the per-family lists disagree — a tool was added to one route and not the other")
    }

    /// Tool names are unique across the whole surface.
    ///
    /// Two tools sharing a name is not a cosmetic clash: the name is the
    /// identifier the model calls by, so one of them becomes unreachable and
    /// which one is undefined.
    func testToolNamesAreUnique() {
        let names = GmAgentTools.all.map(\.name)
        let duplicates = Dictionary(grouping: names, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        XCTAssertTrue(duplicates.isEmpty, "duplicate tool names: \(duplicates)")
    }

    /// Every tool has a non-empty description.
    ///
    /// This matters more than it looks. `description` is the ONLY member of
    /// FoundationModels' `Tool` protocol with no default implementation — `name`,
    /// `parameters` and `includesSchemaInInstructions` are all defaulted — so it
    /// is both the one thing every conformance must author AND the one thing a
    /// hurried conformance will satisfy with `""` to quiet the compiler. An empty
    /// description is a tool the model cannot choose correctly, and it fails
    /// silently rather than loudly.
    func testEveryToolHasADescription() {
        for tool in GmAgentTools.all {
            XCTAssertFalse(
                tool.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(tool.name) has an empty description")
        }
    }

    /// Every tool's `family` matches the namespace it is filed under.
    ///
    /// The family comes from a defaulted extension on the marker protocol, so
    /// this catches a tool conforming to the wrong marker — which compiles
    /// perfectly and puts the tool in the wrong place.
    func testEveryToolIsFiledUnderItsOwnFamily() {
        for family in GmAgentToolFamily.allCases {
            for tool in GmAgentTools.tools(in: family) {
                XCTAssertEqual(
                    tool.family, family,
                    "\(tool.name) is filed under \(family.rawValue) but reports \(tool.family.rawValue)")
            }
        }
    }

    /// Every family has at least one tool.
    ///
    /// This is what the three placeholder tools buy. A family added to the enum
    /// and then never implemented would otherwise exist as a name nothing backs,
    /// and nothing would say so.
    func testEveryFamilyHasAtLeastOneTool() {
        for family in GmAgentToolFamily.allCases {
            XCTAssertFalse(
                GmAgentTools.tools(in: family).isEmpty,
                "family \(family.rawValue) has no tools — add one, or a placeholder that refuses honestly")
        }
    }

    /// The seven families, named explicitly.
    ///
    /// A change-detector on purpose, and a cheap one: adding or removing a family
    /// is a decision, and this makes it one somebody has to confirm rather than
    /// something a refactor can do quietly.
    func testFamilyVocabulary() {
        XCTAssertEqual(
            GmAgentToolFamily.allCases.map(\.rawValue),
            ["dope", "kbite", "diagram", "cde", "projects", "system", "fs"])
    }

    /// Nothing in this surface is wired yet, and the errors say so specifically.
    ///
    /// The point is not that the calls fail — it is that they fail with a message
    /// naming what is missing. A tool that threw a bare error, or worse returned
    /// an empty success, would be indistinguishable from a real empty result.
    func testUnsupportedToolsRefuseWithAReason() async {
        do {
            _ = try await GmAgentTools.diagram.notSupported.call(arguments: GmAgentNoArguments())
            XCTFail("placeholder tool returned a value instead of refusing")
        } catch let error as GmAgentToolError {
            guard case .notImplemented(let family) = error else {
                return XCTFail("expected notImplemented, got \(error)")
            }
            XCTAssertEqual(family, .diagram)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
