import Foundation
import GRDB
import GmDaemon
import GmDaemonSdk
import XCTest

/// The kernel comes up on a fresh root, migrates itself, and answers.
///
/// This is the case that justifies the whole shared-environment design: none of
/// it is observable from a unit test, because all of it is about a real process
/// doing real startup work against a real empty directory.
final class KernelLifecycleTests: KernelBackedTestCase {

    /// A fresh root self-bootstraps. No seeding, no fixtures, no `Store`.
    ///
    /// `KernelWriter.start` migrates an empty directory into a full schema, so
    /// "create a directory and point a kernel at it" is the entire setup — which
    /// is also why pre-seeding an environment is optional rather than required.
    func testAFreshRootMigratesItselfToHead() throws {
        let db = try env.readOnlyDatabase()
        let head = try db.read { try Int.fetchOne($0, sql: "SELECT MAX(version) FROM schema_migrations") }
        XCTAssertEqual(head, Migrations.currentSchemaVersion,
                       "a booted kernel must leave its db at the schema its binary knows")
    }

    /// The kernel answers PING with its own identity, and the protocol version
    /// it reports IS the one this build compiled against.
    func testPingReportsThisBuildsProtocolVersion() throws {
        let pong = try env.send(.ping, PingRequest(), PingResponse.self)
        XCTAssertEqual(pong.protocolVersion, GmWireProtocol.version)
        XCTAssertGreaterThan(pong.daemonPid, 0)
    }

    /// The kernel that answered is the WRITER, and it reports the root it
    /// actually resolved.
    ///
    /// The root assertion is the load-bearing half. It proves the spawned child
    /// landed on the harness's temporary root rather than on `~/gmfs` — which is
    /// exactly the failure `DaemonClient.spawnDaemon` used to have, where an app
    /// resolving its root from a bundle spawned a writer that inherited nothing
    /// and silently opened production.
    func testTheKernelIsTheWriterAndNamesItsOwnRoot() throws {
        let pong = try env.send(.ping, PingRequest(), PingResponse.self)
        XCTAssertEqual(pong.writerRole, "writer")
        let reported = try XCTUnwrap(pong.gmfsRoot)
        XCTAssertEqual(
            URL(fileURLWithPath: reported).standardizedFileURL.path,
            env.root.standardizedFileURL.path,
            "the spawned kernel must be on the harness root, NOT the installed runtime")
    }

    /// The kernel's own boot write is visible in SQL.
    ///
    /// `recordDaemonStart` runs during `KernelWriter.start`, so this asserts the
    /// full round trip — process spawned, lock taken, database opened, migration
    /// ledger advanced, event appended — using nothing but a read-only query.
    /// No fixture, no `@testable`, no `Store`.
    func testTheKernelRecordsItsOwnStart() throws {
        let db = try env.readOnlyDatabase()
        let starts = try db.read {
            try Int.fetchOne($0,
                sql: "SELECT COUNT(*) FROM daemon_event WHERE kind = ?",
                arguments: [DaemonEventKind.daemonStart.rawValue])
        }
        XCTAssertGreaterThan(starts ?? 0, 0, "a booted kernel must record its own start")
    }

    /// Every message type the build knows has a registry row.
    ///
    /// This used to be `VerbRegistryTests`, which was deleted with the rest of
    /// the old suite. It is cheap enough to keep here and it guards a real
    /// hazard: a verb with no row is a WRITE the permission layer cannot see.
    func testEveryMessageTypeHasARegistryRow() {
        let transportOnly: Set<MessageType> = [.hello, .subscribe, .event, .error]
        for type in MessageType.allCases where !transportOnly.contains(type) {
            XCTAssertNotNil(
                VerbRegistry.spec(for: type),
                "\(type.rawValue) has no VerbRegistry row — the guard cannot see it")
        }
    }
}
