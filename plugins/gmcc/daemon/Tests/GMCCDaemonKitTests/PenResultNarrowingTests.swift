import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The regression this file exists for, observed for real: a pen `arch_get`
/// returned 79,598 characters, was REFUSED by the agent harness for exceeding
/// max tokens, and came back as a body cut mid-array. Sorted-key JSON puts
/// `options` before `persistence_changes`, so the cut ate the ENTIRE
/// persistence set without a word — and the refusal told the caller to
/// "narrow the query", which ArchGetRequest had no way to do.
///
/// Two halves are covered here: the structural window on the record reads
/// (arch/clarify/care-package), and the generic size guard that degrades a
/// too-large result instead of emitting one.
final class PenResultNarrowingTests: XCTestCase {
    private var store: Store!
    private var dbPath: String!
    private var promptUuid: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("pen-narrow-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO project (uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES ('proj-1', 0, '\(now)', '\(now)', 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES ('inst-1', 0, '\(now)', '\(now)', 'proj-1', 'repo_1', 'repo_1', '/tmp/pen-narrow-repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES ('sess-1', 0, '\(now)', '\(now)', 'inst-1', 'main', 'main', '', '', 'active',
                        'projects/repo/instances/repo_1/sessions/main');
                """)
        }
        promptUuid = try store.createPrompt(PromptCreateRequest(
            sessionUuid: "sess-1", name: "pen_narrowing", detail: "d")).uuid
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Fixture

    /// A team-shaped architecture: three architect essays, two persistence
    /// changes, three general changes with fat change_code. Deliberately the
    /// shape that blew the budget.
    @discardableResult
    private func seedArchitecture(
        optionBody: String = String(repeating: "essay ", count: 200),
        changeCode: String = String(repeating: "let x = 1\n", count: 200)
    ) throws -> (summaryUuid: String, optionUuids: [String], generalUuids: [String]) {
        let arch = try store.archOpen(ArchOpenRequest(promptUuid: promptUuid)).summary
        var optionUuids: [String] = []
        for name in ["aggressive", "conservative", "pragmatic"] {
            optionUuids.append(try store.archOptionAdd(ArchOptionAddRequest(
                summaryUuid: arch.uuid, agentName: name,
                body: "\(name): \(optionBody)")).option.uuid)
        }
        // Only a decided architecture may expand into change rows.
        let winner = optionUuids[0]
        let summaryVersion = try store.archGet(ArchGetRequest(promptUuid: promptUuid)).summary.version
        _ = try store.archDecide(ArchDecideRequest(
            optionUuid: winner, expectedVersion: summaryVersion, rationale: "it won"))

        for index in 0..<2 {
            _ = try store.archPersistAdd(ArchPersistAddRequest(
                summaryUuid: arch.uuid, className: "Model\(index)",
                filePath: "Sources/Model\(index).swift", reasonBrief: "persistence first"))
        }
        var generalUuids: [String] = []
        for index in 0..<3 {
            generalUuids.append(try store.archGeneralAdd(ArchGeneralAddRequest(
                summaryUuid: arch.uuid, filePath: "Sources/View\(index).swift",
                reasonBrief: "view \(index)", changeDepth: .draft,
                changeCode: changeCode)).change.uuid)
        }
        return (arch.uuid, optionUuids, generalUuids)
    }

    // MARK: - The wire default

    /// BACK-COMPAT IS LOAD-BEARING. A request carrying none of the new fields
    /// must return exactly what ARCH_GET has always returned — full bodies,
    /// full change_code, and NOT ONE of the additive response keys — so a peer
    /// built against the old package (GMVibes) is unchanged by construction
    /// and the wire version does not bump.
    func testWireDefaultIsUnchangedForARequestWithNoNewFields() throws {
        let seeded = try seedArchitecture()
        let got = try store.archGet(ArchGetRequest(promptUuid: promptUuid))

        XCTAssertEqual(got.options.count, 3)
        XCTAssertTrue(got.options.allSatisfy { $0.body.count > 400 })
        XCTAssertEqual(got.generalChanges.count, seeded.generalUuids.count)
        XCTAssertTrue(got.generalChanges.allSatisfy { $0.changeCode.count > 400 })
        XCTAssertNil(got.optionStubs)
        XCTAssertNil(got.generalChangeStubs)
        XCTAssertNil(got.changePage)

        // And the additive keys are ABSENT from the encoded payload, not
        // merely nil in Swift — absence is what an old decoder needs.
        let json = try encodedObject(got)
        XCTAssertNil(json["optionStubs"])
        XCTAssertNil(json["generalChangeStubs"])
        XCTAssertNil(json["changePage"])
        XCTAssertNotNil(json["persistenceChanges"])
    }

    /// The same guarantee for the other two unwindowed record dumps.
    func testClarifyAndCarePackageWireDefaultsAreUnchanged() throws {
        let package = try seedCarePackage()
        let clarify = try store.clarifyGet(ClarifyGetRequest(promptUuid: promptUuid))
        XCTAssertNotNil(clarify.carePackage)
        XCTAssertNil(clarify.carePackageStub)
        XCTAssertNil(clarify.noteStubs)
        XCTAssertEqual(clarify.notes.count, 2)

        let got = try store.carePackageGet(CarePackageGetRequest(promptUuid: promptUuid))
        XCTAssertEqual(got.package.explorationRefs.count, package.refCount)
        XCTAssertNil(got.explorationRefStubs)
    }

    // MARK: - Narrowed arch_get

    /// Narrowing hides CONTENT, never EXISTENCE: the option bodies go, the
    /// option roster stays, and the decision rationale (which lives on the
    /// summary) is still there to say which one won.
    func testNarrowedArchGetOmitsOptionBodiesButNeverAnOptionsExistence() throws {
        let seeded = try seedArchitecture()
        let got = try store.archGet(ArchGetRequest(
            promptUuid: promptUuid, includeOptions: false, full: false))

        XCTAssertTrue(got.options.isEmpty)
        let stubs = try XCTUnwrap(got.optionStubs)
        XCTAssertEqual(Set(stubs.map(\.uuid)), Set(seeded.optionUuids))
        XCTAssertEqual(stubs.filter(\.selected).count, 1)
        XCTAssertTrue(stubs.allSatisfy { $0.bodyChars > 400 })
        XCTAssertEqual(got.summary.decisionRationale, "it won")

        // change_code likewise: excerpt + true length + an honest flag.
        let changeStubs = try XCTUnwrap(got.generalChangeStubs)
        XCTAssertEqual(changeStubs.count, 3)
        for stub in changeStubs {
            XCTAssertEqual(stub.changeCodeExcerpt.count, PenExcerpt.chars)
            XCTAssertTrue(stub.changeCodeTruncated)
            XCTAssertGreaterThan(stub.changeCodeChars, stub.changeCodeExcerpt.count)
        }
        XCTAssertTrue(got.generalChanges.isEmpty)
    }

    /// THE SILENT-TRUNCATION REGRESSION. persistence_changes sorts after
    /// "options" and was eaten whole by the clip; it must be present and
    /// complete in EVERY form of the response — default, narrowed, paged, and
    /// single-row.
    func testPersistenceChangesArePresentInEveryFormOfTheResponse() throws {
        try seedArchitecture()
        let requests: [(String, ArchGetRequest)] = [
            ("default", ArchGetRequest(promptUuid: promptUuid)),
            ("narrowed", ArchGetRequest(promptUuid: promptUuid, includeOptions: false, full: false)),
            ("paged", ArchGetRequest(promptUuid: promptUuid, includeOptions: false, full: false, limit: 1)),
            ("second page", ArchGetRequest(
                promptUuid: promptUuid, includeOptions: false, full: false, limit: 1, cursor: "1")),
            ("options only", ArchGetRequest(promptUuid: promptUuid, includeOptions: true, full: false)),
        ]
        for (label, request) in requests {
            let got = try store.archGet(request)
            XCTAssertEqual(
                got.persistenceChanges.map(\.filePath),
                ["Sources/Model0.swift", "Sources/Model1.swift"],
                "persistence changes went missing in the '\(label)' form")
            let json = try encodedObject(got)
            XCTAssertNotNil(json["persistenceChanges"], "'\(label)' encoded without persistenceChanges")
        }
    }

    /// Naming ONE uuid returns that one body in full — the escape hatch that
    /// makes the stub form usable rather than merely small.
    func testOptionUuidAndChangeUuidReturnFullContent() throws {
        let seeded = try seedArchitecture()

        let option = try store.archGet(ArchGetRequest(
            promptUuid: promptUuid, optionUuid: seeded.optionUuids[1]))
        XCTAssertEqual(option.options.map(\.uuid), [seeded.optionUuids[1]])
        XCTAssertGreaterThan(option.options[0].body.count, 400)
        // The roster still lists all three, so asking for one never hides two.
        XCTAssertEqual(try XCTUnwrap(option.optionStubs).count, 3)

        let change = try store.archGet(ArchGetRequest(
            promptUuid: promptUuid, changeUuid: seeded.generalUuids[2]))
        XCTAssertEqual(change.generalChanges.map(\.uuid), [seeded.generalUuids[2]])
        XCTAssertGreaterThan(change.generalChanges[0].changeCode.count, 400)
        XCTAssertEqual(try XCTUnwrap(change.generalChangeStubs).count, 3)
    }

    /// Paging covers the general rows and reports what was NOT returned, so a
    /// caller is never left guessing whether it saw everything.
    func testPagingReportsTheWholeSetAndContinues() throws {
        let seeded = try seedArchitecture()
        let first = try store.archGet(ArchGetRequest(
            promptUuid: promptUuid, includeOptions: false, full: false, limit: 2))
        let page = try XCTUnwrap(first.changePage)
        XCTAssertEqual(page.returned, 2)
        XCTAssertEqual(page.totalGeneralChanges, 3)
        let cursor = try XCTUnwrap(page.nextCursor)

        let second = try store.archGet(ArchGetRequest(
            promptUuid: promptUuid, includeOptions: false, full: false, limit: 2, cursor: cursor))
        XCTAssertEqual(try XCTUnwrap(second.changePage).returned, 1)
        XCTAssertNil(try XCTUnwrap(second.changePage).nextCursor)
        XCTAssertEqual(
            try XCTUnwrap(second.generalChangeStubs).map(\.uuid), [seeded.generalUuids[2]])
    }

    // MARK: - Narrowed clarify_get / care_package_get

    /// A narrowed-away care package is distinguishable from an absent one —
    /// the stub is what keeps "nil means never opened" true.
    func testNarrowedClarifyGetKeepsThePackageAndTheNotesVisible() throws {
        _ = try seedCarePackage()
        let got = try store.clarifyGet(ClarifyGetRequest(
            promptUuid: promptUuid, includeCarePackage: false, noteWeightMax: 0))

        XCTAssertNil(got.carePackage)
        let stub = try XCTUnwrap(got.carePackageStub)
        XCTAssertEqual(stub.explorationRefCount, 2)
        XCTAssertGreaterThan(stub.clarifiedIntentChars, 0)

        // weight 0 stays full, weight 500 drops to a stub that still carries
        // an excerpt — a note has no title, so a body-less stub is unreadable.
        XCTAssertEqual(got.notes.count, 1)
        XCTAssertEqual(got.notes[0].weight, 0)
        let noteStubs = try XCTUnwrap(got.noteStubs)
        XCTAssertEqual(noteStubs.map(\.weight), [500])
        XCTAssertFalse(noteStubs[0].bodyExcerpt.isEmpty)
    }

    /// CARE_PACKAGE_GET empties an array and names what left it; it never
    /// rewrites a field, so nothing inside a CarePackageRow is ever a
    /// truncated lie — and the clarified intent always comes back whole.
    func testNarrowedCarePackageGetStubsRefsAndKeepsTheIntent() throws {
        let seeded = try seedCarePackage()
        let got = try store.carePackageGet(CarePackageGetRequest(
            promptUuid: promptUuid, includeRefBodies: false))
        XCTAssertTrue(got.package.explorationRefs.isEmpty)
        XCTAssertEqual(try XCTUnwrap(got.explorationRefStubs).count, 2)
        XCTAssertEqual(got.package.clarifiedIntent, seeded.intent)

        let one = try store.carePackageGet(CarePackageGetRequest(
            promptUuid: promptUuid, includeRefBodies: false, refUuid: seeded.refUuids[1]))
        XCTAssertEqual(one.package.explorationRefs.map(\.uuid), [seeded.refUuids[1]])
        XCTAssertGreaterThan(one.package.explorationRefs[0].curatedBody.count, 400)
        XCTAssertEqual(try XCTUnwrap(one.explorationRefStubs).count, 2)
    }

    // MARK: - The generic size guard

    /// Over budget WITH somewhere to fall back to: data plus instructions,
    /// never a refusal and never a clipped body.
    func testSizeGuardDegradesInsteadOfEmittingAnOversizedBody() throws {
        // A body big enough to reproduce the real failure: option essays and
        // change_code that together clear the budget several times over.
        try seedArchitecture(
            optionBody: String(repeating: "essay ", count: 6_000),
            changeCode: String(repeating: "let x = 1\n", count: 6_000))

        let fat = try store.archGet(ArchGetRequest(promptUuid: promptUuid))
        let fatBytes = try PenResultBudget.encoder().encode(fat).count
        XCTAssertGreaterThan(fatBytes, PenResultBudget.maxBytes)

        let rendered = try PenResultBudget.render(
            tool: "arch_get",
            narrowing: PenNarrowing(parameters: ["limit", "option_uuid"], retryWith: "arch_get with limit=10"),
            value: fat,
            degrade: {
                try self.store.archGet(ArchGetRequest(
                    promptUuid: self.promptUuid, includeOptions: false, full: false, limit: 10))
            })

        // WELL-FORMED JSON, ALWAYS. Hand-parsing a truncated body is the
        // failure being fixed, so the output must survive a real parse.
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any])
        let note = try XCTUnwrap(parsed["gmcc_oversize"] as? [String: Any])
        XCTAssertEqual(note["tool"] as? String, "arch_get")
        XCTAssertEqual(note["outcome"] as? String, "degraded")
        XCTAssertEqual(note["budgetBytes"] as? Int, PenResultBudget.maxBytes)
        XCTAssertEqual(note["bytes"] as? Int, fatBytes)
        // The advice names the parameter that narrows THIS tool — the old
        // "narrow the query (rating windows, limit)" named none that existed.
        XCTAssertEqual(note["parameters"] as? [String], ["limit", "option_uuid"])
        XCTAssertEqual(note["retryWith"] as? String, "arch_get with limit=10")

        // And real data rode along, persistence set intact.
        let result = try XCTUnwrap(parsed["result"] as? [String: Any])
        XCTAssertEqual((result["persistenceChanges"] as? [Any])?.count, 2)
        XCTAssertEqual((result["optionStubs"] as? [Any])?.count, 3)
        XCTAssertLessThanOrEqual(rendered.utf8.count, PenResultBudget.maxBytes * 2)
        XCTAssertFalse(rendered.contains("TRUNCATED"))
    }

    /// Over budget with NOTHING to fall back to — a tool whose result is one
    /// indivisible record. The caller gets the note ALONE: no `result` key is
    /// a fact it can act on, a half-parsed body is not.
    func testSizeGuardWithholdsRatherThanTruncatingWhenThereIsNoNarrowing() throws {
        let huge = String(repeating: "x", count: PenResultBudget.maxBytes + 1_000)
        let rendered = try PenResultBudget.render(
            tool: "kbite_file_get", narrowing: nil, value: ["content": huge])
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any])
        XCTAssertNil(parsed["result"])
        let note = try XCTUnwrap(parsed["gmcc_oversize"] as? [String: Any])
        XCTAssertEqual(note["outcome"] as? String, "withheld")
        XCTAssertEqual(note["parameters"] as? [String], [])
        XCTAssertTrue(
            try XCTUnwrap(note["retryWith"] as? String).contains("no narrowing parameter"))
    }

    /// Under budget: the payload verbatim, no envelope, nothing new to parse.
    func testSizeGuardIsInvisibleForAResultThatFits() throws {
        try seedArchitecture()
        let got = try store.archGet(ArchGetRequest(promptUuid: promptUuid))
        let rendered = try PenResultBudget.render(tool: "arch_get", narrowing: nil, value: got)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any])
        XCTAssertNil(parsed["gmcc_oversize"])
        XCTAssertNotNil(parsed["persistenceChanges"])
    }

    // MARK: - Helpers

    private func encodedObject(_ value: any Encodable) throws -> [String: Any] {
        let data = try PenResultBudget.encoder().encode(AnyEncodable(value))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @discardableResult
    private func seedCarePackage() throws
        -> (packageUuid: String, refUuids: [String], refCount: Int, intent: String)
    {
        let clarify = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: promptUuid)).summary
        _ = try store.clarifyNoteAdd(ClarifyNoteAddRequest(
            summaryUuid: clarify.uuid, body: "critical", weight: 0))
        _ = try store.clarifyNoteAdd(ClarifyNoteAddRequest(
            summaryUuid: clarify.uuid,
            body: String(repeating: "background ", count: 100), weight: 500))

        let package = try store.carePackageOpen(CarePackageOpenRequest(
            summaryUuid: clarify.uuid)).package
        var refUuids: [String] = []
        for index in 0..<2 {
            let updated = try store.carePackageRefAdd(CarePackageRefAddRequest(
                packageUuid: package.uuid, kind: .exploration,
                curatedTitle: "finding \(index)",
                curatedBody: String(repeating: "copied finding text ", count: 100))).package
            refUuids.append(try XCTUnwrap(updated.explorationRefs.last).uuid)
        }
        let intent = "build the thing"
        let current = try store.carePackageGet(CarePackageGetRequest(promptUuid: promptUuid)).package
        _ = try store.carePackageComplete(CarePackageCompleteRequest(
            packageUuid: package.uuid, expectedVersion: current.version, clarifiedIntent: intent))
        return (package.uuid, refUuids, refUuids.count, intent)
    }
}
