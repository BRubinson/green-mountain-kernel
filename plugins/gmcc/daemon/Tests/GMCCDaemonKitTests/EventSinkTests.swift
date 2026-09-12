import GRDB
import XCTest
@testable import GMCCDaemonKit

/// The post-commit event sink — the daemon's ONLY push channel, and until this
/// file the only load-bearing piece of the persistence layer with zero
/// coverage. Server.swift registers exactly one closure on it; every SUBSCRIBE
/// client, every GMVibes live refresh, and the watcher-stack rebuild ride on
/// that one assignment.
///
/// This test exists because the failure mode is invisible: a lost `set` on the
/// accessor, a core held weakly, or a batched `afterNextTransaction` staging
/// leaves the daemon looking perfectly healthy while it goes silently mute,
/// with the whole suite still green. It is written against the CURRENT Store
/// deliberately — it lands before the StoreCore extraction so the extraction is
/// guarded rather than trusted.
///
/// Deliberately NOT asserted: which queue the sink runs on. GRDB fires
/// afterNextTransaction(onCommit:) on the DATABASE's serialized queue, and
/// Server.swift documents why a dispatchPrecondition there would trap. Nothing
/// in this file may re-enter dbQueue from inside the sink.
final class EventSinkTests: XCTestCase {

    private var store: Store!
    private var dbPath: String!

    override func setUpWithError() throws {
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("event-sink-\(UUID().uuidString).db").path
        store = try Store(path: dbPath)
        try store.migrate()
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    /// A committed event fires the sink exactly once, and the broadcast copy is
    /// identical to what a later EVENT_LIST replay would return.
    ///
    /// The id assertion pins appendEvent's dependency on `db.lastInsertedRowID`
    /// being read immediately after insertBase returns; the createdAt assertion
    /// pins its single-timestamp invariant (one isoNow() reused for both the row
    /// and the sink copy). Both are silent if broken — the sink would still
    /// fire, just with a value that disagrees with the persisted row.
    func testCommittedEventFiresOnceAndMatchesThePersistedRow() throws {
        var received: [PersistedEvent] = []
        store.eventSink = { received.append($0) }

        try store.dbQueue.write { db in
            try store.appendEvent(db, kind: .daemonStart, subjectUuid: "subject-1", payload: "{}")
        }

        XCTAssertEqual(received.count, 1, "one committed event must fire the sink exactly once")
        let event = try XCTUnwrap(received.first)
        XCTAssertEqual(event.kind, DaemonEventKind.daemonStart.rawValue)
        XCTAssertEqual(event.subjectUuid, "subject-1")
        XCTAssertEqual(event.payload, "{}")

        let row = try store.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT id, kind, subject_uuid, payload, created_at FROM daemon_event")
        }
        let persisted = try XCTUnwrap(row)
        XCTAssertEqual(event.id, persisted["id"] as Int64,
                       "sink id must be the committed rowid (lastInsertedRowID read right after insertBase)")
        XCTAssertEqual(event.createdAt, persisted["created_at"] as String,
                       "sink and row must share ONE timestamp, so a live broadcast and a later replay agree")
    }

    /// The sink fires only AFTER commit — a rolled-back write can never leak a
    /// phantom event, and leaves no row behind either.
    func testRolledBackTransactionFiresNothingAndPersistsNothing() throws {
        var received: [PersistedEvent] = []
        store.eventSink = { received.append($0) }

        struct Abort: Error {}
        XCTAssertThrowsError(
            try store.dbQueue.write { db in
                try store.appendEvent(db, kind: .daemonStart, subjectUuid: "doomed")
                throw Abort()
            }
        )

        XCTAssertEqual(received.count, 0, "a rolled-back write must not leak a phantom event")
        let count = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daemon_event") ?? -1
        }
        XCTAssertEqual(count, 0)
    }

    /// One observer per EVENT, not per transaction: appendEvent registers a
    /// fresh afterNextTransaction handler per call, so N events in a single
    /// write fire N times on the one commit, in append order. Collapsing that
    /// into a staged batch would change both ordering and the id/timestamp
    /// pairing.
    func testEachEventInOneTransactionFiresSeparatelyInOrder() throws {
        var received: [PersistedEvent] = []
        store.eventSink = { received.append($0) }

        try store.dbQueue.write { db in
            try store.appendEvent(db, kind: .daemonStart, subjectUuid: "first")
            try store.appendEvent(db, kind: .daemonStop, subjectUuid: "second")
            try store.appendEvent(db, kind: .daemonStart, subjectUuid: "third")
        }

        XCTAssertEqual(received.map(\.subjectUuid), ["first", "second", "third"])
        XCTAssertEqual(received.map(\.id), received.map(\.id).sorted(),
                       "sink order must follow append order")
    }

    /// Assignment reaches the real storage, in both directions.
    ///
    /// This is the assertion that catches the specific regression the StoreCore
    /// extraction can introduce: if `Store.eventSink` becomes a stored property
    /// copied into the core at init rather than a real get/set forward, then
    /// Server.swift's assignment — which happens AFTER Store construction —
    /// silently does nothing, and every one of these events disappears.
    func testSinkIsReassignableAndClearable() throws {
        var first: [PersistedEvent] = []
        var second: [PersistedEvent] = []

        store.eventSink = { first.append($0) }
        try store.dbQueue.write { db in try store.appendEvent(db, kind: .daemonStart) }
        XCTAssertEqual(first.count, 1)

        // Reassign after the first write: the new closure must take over.
        store.eventSink = { second.append($0) }
        try store.dbQueue.write { db in try store.appendEvent(db, kind: .daemonStart) }
        XCTAssertEqual(first.count, 1, "the replaced closure must stop receiving")
        XCTAssertEqual(second.count, 1)

        // Clearing must be observable too, and must not trap on a nil sink.
        store.eventSink = nil
        XCTAssertNil(store.eventSink)
        try store.dbQueue.write { db in try store.appendEvent(db, kind: .daemonStart) }
        XCTAssertEqual(second.count, 1, "a cleared sink must receive nothing")

        let count = try store.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daemon_event") ?? -1
        }
        XCTAssertEqual(count, 3, "clearing the sink must not affect persistence")
    }
}
