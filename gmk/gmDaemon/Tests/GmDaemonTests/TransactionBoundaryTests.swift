import GRDB
import XCTest
@testable import GmDaemon
import GmDaemonSdk

/// The ambient transaction boundary — the shared-service-layer deliverable.
///
/// Two kinds of test live here and they fail for different reasons, which is
/// why they are together. The BEHAVIOURAL cases prove composition actually
/// works: two verbs inside one `inTransaction` commit together or not at all.
/// The SOURCE-SCAN cases pin the two invariants the mechanism silently depends
/// on — that nothing bypasses the boundary, and that the verb layer performs no
/// thread hops. Neither invariant is visible at a call site, so without these a
/// future edit would break the boundary while every behavioural test stayed
/// green.
final class TransactionBoundaryTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tx-boundary-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
        // Raw seeding, matching the convention in CarePackageStalenessTests: a
        // test fixture is allowed to reach dbQueue directly, and the
        // boundary's source scan is scoped to Sources/ for exactly that reason.
        try store.dbQueue.write { db in
            let now = Store.isoNow()
            func base(_ uuid: String) -> String { "NULL, '\(uuid)', 0, '\(now)', '\(now)'" }
            try db.execute(sql: """
                INSERT INTO project (id, uuid, version, created_at, updated_at,
                    git_repo_name, code, name, gmfs_relative_storage_path)
                VALUES (\(base("proj-1")), 'repo', 'repo', 'repo', 'projects/repo');
                INSERT INTO instance (id, uuid, version, created_at, updated_at,
                    project_uuid, code, name, absolute_file_system_path, gmfs_relative_storage_path)
                VALUES (\(base("inst-1")), 'proj-1', 'repo_1', 'repo_1', '/tmp/repo',
                        'projects/repo/instances/repo_1');
                INSERT INTO session (id, uuid, version, created_at, updated_at,
                    instance_uuid, code, name, backstory, goal, status, gmfs_relative_storage_path)
                VALUES (\(base("sess-1")), 'inst-1', 'main', 'main', '', '', 'active', 'x');
                INSERT INTO prompt (id, uuid, version, created_at, updated_at,
                    session_uuid, seq, code, name, backstory, goal, detail, command, status,
                    gmfs_relative_storage_path)
                VALUES (\(base("prompt-a")), 'sess-1', 1, 'p1', 'one', '', '', '', '', 'draft', '');
                """)
        }
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - Composition

    /// The headline property: two writes to DIFFERENT tables inside one
    /// transaction are one commit.
    func testTwoWritesInOneTransactionBothLand() throws {
        try store.inTransaction {
            _ = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a"))
            _ = try store.reviewOpen(ReviewOpenRequest(promptUuid: "prompt-a"))
        }

        XCTAssertNotNil(
            try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a")).summary,
            "the clarification summary should have committed")
        XCTAssertNotNil(
            try store.reviewGet(ReviewGetRequest(promptUuid: "prompt-a")).summary,
            "the review summary should have committed in the SAME transaction")
    }

    /// The half that matters more: a failure anywhere in the composite leaves
    /// NOTHING behind. Without the enlist this would commit the first write and
    /// then fail, which is the silent partial write the boundary exists to make
    /// impossible.
    func testFailureInsideTransactionRollsBackEverything() throws {
        struct Sentinel: Error {}
        XCTAssertThrowsError(
            try store.inTransaction {
                _ = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a"))
                _ = try store.reviewOpen(ReviewOpenRequest(promptUuid: "prompt-a"))
                throw Sentinel()
            }
        )

        // Absence shows up as SUMMARY_ABSENT rather than a nil summary: the get
        // verbs distinguish "never opened" from "opened and empty", which is the
        // stronger signal here — it says the row was never created at all.
        assertSummaryAbsent(
            "clarification",
            try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a")),
            "the FIRST write must be rolled back too — this is the partial-write case")
        assertSummaryAbsent(
            "review",
            try store.reviewGet(ReviewGetRequest(promptUuid: "prompt-a")),
            "the second write must be rolled back")
    }

    /// Asserts a get verb refused with `summaryAbsent` for `entity`, which is
    /// how this schema reports "no such row".
    private func assertSummaryAbsent<T>(
        _ entity: String,
        _ expression: @autoclosure () throws -> T,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("expected StoreError.summaryAbsent(\(entity)) — \(message)",
                    file: file, line: line)
        } catch StoreError.summaryAbsent(let got, _) {
            XCTAssertEqual(got, entity, message, file: file, line: line)
        } catch {
            XCTFail("expected StoreError.summaryAbsent(\(entity)), got \(error) — \(message)",
                    file: file, line: line)
        }
    }

    /// Nesting enlists rather than opening a second transaction. If it did not,
    /// GRDB's re-entrancy check would TRAP and take the process with it — so a
    /// regression here is a crash, not a failure, and that is exactly why it is
    /// pinned.
    func testNestedInTransactionEnlistsRatherThanTrapping() throws {
        try store.inTransaction {
            try store.inTransaction {
                _ = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a"))
            }
        }
        XCTAssertFalse(store.isInTransaction, "the ambient handle must be cleared on exit")
    }

    /// A read issued inside a write must enlist. `DatabaseQueue` holds ONE
    /// connection, so a raw `dbQueue.read` here would re-enter and trap; and
    /// even if it did not, it would read a snapshot that cannot see the write
    /// its own caller just made.
    func testReadInsideTransactionSeesTheUncommittedWrite() throws {
        try store.inTransaction {
            _ = try store.clarifyOpen(ClarifyOpenRequest(promptUuid: "prompt-a"))
            // A READ, inside the same open write transaction.
            let seen = try store.clarifyGet(ClarifyGetRequest(promptUuid: "prompt-a"))
            XCTAssertNotNil(seen.summary,
                            "an enlisted read must see the transaction's own uncommitted write")
        }
    }

    /// The ambient handle must not survive the boundary, or the NEXT unrelated
    /// verb on this thread would silently join a transaction that is already
    /// committed.
    func testAmbientHandleIsClearedAfterTheBoundary() throws {
        XCTAssertFalse(store.isInTransaction)
        try store.inTransaction {
            XCTAssertTrue(store.isInTransaction)
        }
        XCTAssertFalse(store.isInTransaction)
    }

    // MARK: - Non-composable verbs

    /// The four-phase repo verbs do filesystem work holding no db lock.
    /// Composing one would pin the single writer across file I/O, so they
    /// refuse — loudly, naming themselves.
    func testFourPhaseRepoVerbRefusesInsideATransaction() throws {
        var thrown: Error?
        XCTAssertThrowsError(
            try store.inTransaction {
                _ = try store.dopeReadRepo(DopeReadRepoRequest(scopeUuid: "whatever"))
            }
        ) { thrown = $0 }

        guard case .some(StoreError.notComposable(let verb)) = thrown as? StoreError else {
            return XCTFail("expected StoreError.notComposable, got \(String(describing: thrown))")
        }
        XCTAssertEqual(verb, "dopeReadRepo")
    }

    /// A WAL checkpoint inside a transaction is illegal in SQLite. Refusing here
    /// names the cause; letting it through would surface as a SQLite error whose
    /// text explains nothing.
    func testCheckpointTruncateRefusesInsideATransaction() throws {
        var thrown: Error?
        XCTAssertThrowsError(
            try store.inTransaction { try store.checkpointTruncate() }
        ) { thrown = $0 }

        guard case .some(StoreError.notComposable(let verb)) = thrown as? StoreError else {
            return XCTFail("expected StoreError.notComposable, got \(String(describing: thrown))")
        }
        XCTAssertEqual(verb, "checkpointTruncate")
    }

    /// And it still works outside one, so the guard did not break the SHUTDOWN
    /// contract it sits in front of.
    func testCheckpointTruncateStillWorksOutsideATransaction() throws {
        XCTAssertNoThrow(try store.checkpointTruncate())
    }

    // MARK: - Source-scan invariants

    /// NOTHING may reach `dbQueue.write` / `dbQueue.read` except the boundary
    /// itself. A direct call would open a second transaction inside an ambient
    /// one and trap, and no behavioural test would catch it until the code path
    /// happened to be composed.
    ///
    /// Three raw uses are legal and enumerated: the checkpoint's
    /// `writeWithoutTransaction`, `close()`, and GRDB's `backup(to:)`, none of
    /// which is a transaction.
    func testNothingBypassesTheBoundary() throws {
        let dir = Self.storeSourceDirectory()
        var offenders: [String] = []

        for url in Self.swiftFiles(under: dir) where url.lastPathComponent != "StoreBoundary.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                // Skip doc comments: the corrected headers legitimately mention
                // the old spelling to explain what replaced it.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                guard line.contains("dbQueue.") else { continue }
                if line.contains("dbQueue.writeWithoutTransaction") { continue }
                if line.contains("dbQueue.close") { continue }
                if line.contains("dbQueue.backup") { continue }
                offenders.append("\(url.lastPathComponent):\(i + 1): \(trimmed)")
            }
        }

        XCTAssertTrue(offenders.isEmpty,
                      "raw dbQueue transaction calls must route through boundary/boundaryRead:\n"
                        + offenders.joined(separator: "\n"))
    }

    /// THE CORRECTNESS CONDITION for a thread-local ambient handle: the verb
    /// layer must not hop threads inside a boundary. GRDB runs a write body
    /// synchronously on one thread, and the handle follows that thread — a
    /// `DispatchQueue.async` or an `await` inside a verb would continue on a
    /// different thread where the ambient handle is absent, silently splitting
    /// one transaction in two.
    ///
    /// Verified at zero occurrences when the boundary landed. If this goes red,
    /// remove the hop — do not relax the boundary.
    func testVerbLayerPerformsNoThreadHops() throws {
        let banned = ["DispatchQueue", "Task {", "Task.detached", " await ", "async let"]
        var offenders: [String] = []

        for url in Self.swiftFiles(under: Self.storeSourceDirectory()) {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                for needle in banned where line.contains(needle) {
                    offenders.append("\(url.lastPathComponent):\(i + 1): \(needle) — \(trimmed)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty,
                      "the verb layer must stay synchronous for the ambient handle to be correct:\n"
                        + offenders.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private static func storeSourceDirectory() -> URL {
        // Tests/GmDaemonTests/<this file> → ../../Sources/GmDaemon
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GmDaemonTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // gmDaemon
            .appendingPathComponent("Sources/GmDaemon")
    }

    private static func swiftFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

}
