import XCTest
import GRDB
@testable import GMCCDaemonKit

/// The care package's half of the shared read-time drift report.
///
/// The EXTRACTION's parity guard is the existing BriefingTests suite, which
/// must never be edited for this change — `DopeRepository.scopeStaleness` and
/// `.dotPathExists` are BriefingRepository's old bodies moved verbatim, so
/// BRIEFING_GET's output stays byte-identical. These tests cover only the new
/// surface: CLARIFY_GET's `care_package_staleness`, its non-nil-iff invariant,
/// and the additive-optional wire contract that lets it ship without a bump.
final class CarePackageStalenessTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("care-staleness-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String {
                "NULL, '\(uuid)', 0, '\(now)', '\(now)'"
            }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, ckfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, ckfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, ckfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    ckfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Helpers

    /// A SESSION_INSTANCE scope holding exactly one resolvable dot-path,
    /// `agentics.care_package`. Anything else a ref names is a ghost.
    private func makeScope(revision: Int64 = 5) throws {
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            try db.execute(sql: """
                INSERT INTO dope_scope (id, uuid, version, created_at, updated_at,
                    project_uuid, instance_uuid, session_uuid, prompt_uuid, scope_type,
                    code, name, description, revision)
                VALUES (NULL, 'scope-1', 0, '\(now)', '\(now)',
                    'proj-1', 'inst-1', 'sess-1', NULL, 'SESSION_INSTANCE',
                    'gmcc', 'GMCC', '', \(revision));
                INSERT INTO dope_persistence (id, uuid, version, created_at, updated_at,
                    dope_scope_uuid, code, name, description, sort_order, content_revision)
                VALUES (NULL, 'dom-1', 0, '\(now)', '\(now)', 'scope-1', 'agentics', 'Agentics', '', 0, 0);
                INSERT INTO dope_persistence_entity (id, uuid, version, created_at, updated_at,
                    dope_persistence_uuid, code, name, entity_type, description, sort_order)
                VALUES (NULL, 'ent-1', 0, '\(now)', '\(now)', 'dom-1', 'care_package', 'Care Package', 'MODEL', '', 0);
                """)
        }
    }

    private func bumpScope(to revision: Int64) throws {
        try store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE dope_scope SET revision = ? WHERE uuid = 'scope-1'",
                arguments: [revision])
        }
    }

    /// open clarify → open package → add the given dope refs.
    @discardableResult
    private func openPackage(dopeCodes: [String]) throws -> CarePackageRow {
        let summary = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a")).summary
        var package = try store.carePackageOpen(
            CarePackageOpenRequest(summaryUuid: summary.uuid)).package
        for code in dopeCodes {
            package = try store.carePackageRefAdd(CarePackageRefAddRequest(
                packageUuid: package.uuid, kind: .dope, dopeCode: code)).package
        }
        return package
    }

    private func completePackage(_ package: CarePackageRow) throws -> CarePackageRow {
        try store.carePackageComplete(CarePackageCompleteRequest(
            packageUuid: package.uuid,
            expectedVersion: package.version,
            clarifiedIntent: "ship the staleness badge")).package
    }

    private func staleness() throws -> CarePackageStaleness? {
        try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a")).carePackageStaleness
    }

    // MARK: - Drift

    func testCompletedPackageOnCurrentScopeIsNotDrifted() throws {
        try makeScope(revision: 5)
        let package = try completePackage(try openPackage(dopeCodes: ["agentics.care_package"]))
        XCTAssertEqual(package.dopeScopeUuid, "scope-1")
        XCTAssertEqual(package.dopeScopeRevision, 5)

        let s = try XCTUnwrap(try staleness())
        XCTAssertEqual(s.stampedRevision, 5)
        XCTAssertEqual(s.currentRevision, 5)
        XCTAssertFalse(s.drifted)
        XCTAssertTrue(s.ghostDotPaths.isEmpty)
    }

    func testRevisionMovingAfterCompleteReportsDrift() throws {
        try makeScope(revision: 5)
        _ = try completePackage(try openPackage(dopeCodes: ["agentics.care_package"]))
        try bumpScope(to: 9)

        let s = try XCTUnwrap(try staleness())
        XCTAssertEqual(s.stampedRevision, 5)
        XCTAssertEqual(s.currentRevision, 9)
        XCTAssertTrue(s.drifted)
        // Drift is the revision counter alone — a still-resolvable ref is not a ghost.
        XCTAssertTrue(s.ghostDotPaths.isEmpty)
    }

    // MARK: - Ghosts

    func testUnresolvableDotPathIsReportedAsAGhost() throws {
        try makeScope(revision: 5)
        _ = try completePackage(try openPackage(dopeCodes: [
            "agentics.care_package",          // resolves
            "agentics.care_package.deleted",  // property never existed
            "no_such_domain",                 // domain never existed
        ]))

        let s = try XCTUnwrap(try staleness())
        XCTAssertFalse(s.drifted)
        // Reported in ref order, and ONLY the unresolvable ones.
        XCTAssertEqual(s.ghostDotPaths, ["agentics.care_package.deleted", "no_such_domain"])
    }

    func testDeletingTheEntityTurnsALiveRefIntoAGhost() throws {
        try makeScope(revision: 5)
        _ = try completePackage(try openPackage(dopeCodes: ["agentics.care_package"]))
        XCTAssertEqual(try XCTUnwrap(try staleness()).ghostDotPaths, [])

        try store.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dope_persistence_entity WHERE uuid = 'ent-1'")
        }
        XCTAssertEqual(
            try XCTUnwrap(try staleness()).ghostDotPaths, ["agentics.care_package"])
    }

    // MARK: - No scope

    func testNilScopeUuidMeansNoDriftAndNoGhosts() throws {
        try makeScope(revision: 5)
        // Still building: package-complete is what stamps the scope, so
        // dope_scope_uuid is NULL here even though refs already name codes
        // that would otherwise ghost.
        let package = try openPackage(dopeCodes: ["no_such_domain"])
        XCTAssertNil(package.dopeScopeUuid)
        XCTAssertNil(package.dopeScopeRevision)

        let s = try XCTUnwrap(try staleness())
        XCTAssertNil(s.stampedRevision)
        XCTAssertNil(s.currentRevision)
        XCTAssertFalse(s.drifted)
        XCTAssertTrue(s.ghostDotPaths.isEmpty)
    }

    func testCompleteWithNoScopeInTheSessionStampsNothing() throws {
        // No makeScope at all — package-complete finds no candidate.
        _ = try completePackage(try openPackage(dopeCodes: ["agentics.care_package"]))

        let s = try XCTUnwrap(try staleness())
        XCTAssertNil(s.stampedRevision)
        XCTAssertNil(s.currentRevision)
        XCTAssertFalse(s.drifted)
        XCTAssertTrue(s.ghostDotPaths.isEmpty)
    }

    // MARK: - The invariant

    func testStalenessIsNonNilIffCarePackageIsNonNil() throws {
        try makeScope(revision: 5)
        _ = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a"))

        // No package opened yet: both halves absent.
        var response = try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a"))
        XCTAssertNil(response.carePackage)
        XCTAssertNil(response.carePackageStaleness)

        // Package opened: both halves present, at every package status.
        let package = try openPackage(dopeCodes: ["agentics.care_package"])
        response = try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a"))
        XCTAssertNotNil(response.carePackage)
        XCTAssertNotNil(response.carePackageStaleness)
        XCTAssertEqual(response.carePackage?.status, "building")

        _ = try completePackage(package)
        response = try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a"))
        XCTAssertEqual(response.carePackage?.status, "ready")
        XCTAssertNotNil(response.carePackageStaleness)
    }

    // MARK: - Wire contract

    /// `care_package_staleness` is an ADDITIVE OPTIONAL on an existing
    /// message, which under CLAUDE.md's rule does NOT bump the version: a
    /// stale peer decodes the unknown key away, and a stale daemon's response
    /// decodes to nil here. The PIN is what makes a bump a decision rather
    /// than a side effect — only a new message type or an incompatible change
    /// may move this number, and GMVibes' local package reference rides on
    /// that rule holding.
    func testWireProtocolVersionIsPinned() {
        XCTAssertEqual(GMCCWireProtocol.version, 25)
    }

    func testStalenessOmittedByAPeerDecodesToNil() throws {
        let summary = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a")).summary
        let legacy = ClarifyGetResponse(
            summary: summary, questions: [], notes: [], carePackage: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try NDJSON.encodeLine(legacy)) as? [String: Any])
        XCTAssertNil(json["care_package_staleness"])

        let decoded = try NDJSON.decode(ClarifyGetResponse.self, from: try NDJSON.encodeLine(legacy))
        XCTAssertNil(decoded.carePackageStaleness)
    }

    func testStalenessRidesTheWireUnderItsSnakeCaseKeys() throws {
        try makeScope(revision: 5)
        _ = try completePackage(try openPackage(dopeCodes: ["no_such_domain"]))
        try bumpScope(to: 6)

        let response = try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a"))
        let data = try NDJSON.encodeLine(response)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let block = try XCTUnwrap(json["care_package_staleness"] as? [String: Any])
        XCTAssertEqual(block["stamped_revision"] as? Int, 5)
        XCTAssertEqual(block["current_revision"] as? Int, 6)
        XCTAssertEqual(block["drifted"] as? Bool, true)
        XCTAssertEqual(block["ghost_dot_paths"] as? [String], ["no_such_domain"])

        let decoded = try NDJSON.decode(ClarifyGetResponse.self, from: data)
        XCTAssertEqual(decoded.carePackageStaleness, response.carePackageStaleness)
    }

    /// Both staleness types render through ONE badge, which is the whole point
    /// of the shared protocol.
    func testBothStalenessTypesReportThroughTheSharedProtocol() throws {
        let reporters: [DopeScopeStalenessReporting] = [
            BriefingStaleness(
                stampedRevision: 1, currentRevision: 2, drifted: true, ghostDotPaths: ["a"]),
            CarePackageStaleness(
                stampedRevision: 1, currentRevision: 2, drifted: true, ghostDotPaths: ["a"]),
        ]
        for reporter in reporters {
            XCTAssertEqual(reporter.stampedRevision, 1)
            XCTAssertEqual(reporter.currentRevision, 2)
            XCTAssertTrue(reporter.drifted)
            XCTAssertEqual(reporter.ghostDotPaths, ["a"])
        }
    }
}
