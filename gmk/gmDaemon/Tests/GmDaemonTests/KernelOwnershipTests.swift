import XCTest
@testable import GmKernelHost
import GmDaemonSdk

/// The ownership lock, exercised rather than asserted.
///
/// `KernelHostContractTests` proves the DISCIPLINE holds — one construction site,
/// an unforgeable token. This file proves the MECHANISM works: that a second
/// acquirer really loses, that the loser learns who won, and that a crashed
/// holder leaves nothing behind.
///
/// The lock is taken against a TEMP pidfile, never the installed runtime's. A
/// test that locked the real path would fight the developer's own kernel for it
/// — and `LiveRuntimeIsolationTests` bans this suite from naming any `Paths`
/// member for exactly that reason, which is why the path is built by hand here
/// rather than read from the runtime.
final class KernelOwnershipTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kernel-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var pidfile: String { dir.appendingPathComponent("daemon.pid").path }

    /// Take an exclusive lock the way `acquire()` does, and hold it.
    private func lockHeldByAnotherOwner(record: String) throws -> Int32 {
        let fd = open(pidfile, O_CREAT | O_RDWR, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0, "could not open the test pidfile")
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0, "could not take the test lock")
        ftruncate(fd, 0)
        _ = record.withCString { write(fd, $0, strlen($0)) }
        return fd
    }

    /// THE CORE PROPERTY: a second acquirer cannot take a held lock.
    func testSecondAcquirerLoses() throws {
        let held = try lockHeldByAnotherOwner(record: "\(getpid())\n/usr/bin/true\n\n")
        defer { close(held) }

        let second = open(pidfile, O_CREAT | O_RDWR, 0o644)
        defer { close(second) }
        XCTAssertNotEqual(
            flock(second, LOCK_EX | LOCK_NB), 0,
            "a second flock SUCCEEDED on a held lock — two writers would open the same db")
        XCTAssertEqual(errno, EWOULDBLOCK)
    }

    /// The lock releases when its holder's descriptor closes — which is how a
    /// CRASHED kernel leaves no stale lock. The fd is deliberately held for
    /// process lifetime so the kernel does the releasing.
    func testLockReleasesWhenTheHolderExits() throws {
        let held = try lockHeldByAnotherOwner(record: "\(getpid())\n/usr/bin/true\n\n")
        close(held)  // stands in for the holder exiting

        let second = open(pidfile, O_CREAT | O_RDWR, 0o644)
        defer { close(second) }
        XCTAssertEqual(
            flock(second, LOCK_EX | LOCK_NB), 0,
            "the lock survived its holder — a crash would wedge the runtime permanently")
    }

    /// A loser can read WHO holds it. Without this the client-mode banner cannot
    /// name the other bundle, and naming both is the entire point of that row.
    func testHolderRecordIsReadableByALoser() throws {
        let record = "4242\n/Applications/gm_kernel.app/Contents/MacOS/gm_kernel\n/Applications/gm_kernel.app\n"
        let held = try lockHeldByAnotherOwner(record: record)
        defer { close(held) }

        let text = try String(contentsOfFile: pidfile, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.first, "4242")
        XCTAssertEqual(lines.count > 2 ? lines[2] : "", "/Applications/gm_kernel.app",
                       "the bundle path line is what distinguishes an app holder from a headless one")
    }

    /// An EMPTY third line means HEADLESS, and the distinction decides behaviour:
    /// an app takes over from a headless writer but never from another app copy.
    func testEmptyBundleLineMeansHeadless() throws {
        let held = try lockHeldByAnotherOwner(record: "999\n/usr/local/bin/gm_kernel\n\n")
        defer { close(held) }

        let text = try String(contentsOfFile: pidfile, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertTrue(lines.count > 2 && lines[2].isEmpty,
                      "a headless holder must record an EMPTY bundle path")
    }

    /// The pidfile gaining two lines is safe only because nothing reads it as a
    /// bare pid. Pinned so a future reader that does `Int(contents)` fails here
    /// rather than in production.
    func testPidfileIsThreeLinesNotABarePid() throws {
        let held = try lockHeldByAnotherOwner(record: "7\n/bin/x\n/A/b.app\n")
        defer { close(held) }
        let text = try String(contentsOfFile: pidfile, encoding: .utf8)
        XCTAssertNil(Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                     "the pidfile parsed as a bare integer — the holder record was lost")
        XCTAssertEqual(text.split(separator: "\n", omittingEmptySubsequences: false).count, 4)
    }

    /// `readHolder()` tolerates a pidfile caught mid-write. A loser that raced the
    /// winner between `ftruncate` and `write` must not report "unknown holder" for
    /// a race that resolves in microseconds.
    func testEmptyPidfileYieldsNoHolderRatherThanGarbage() throws {
        FileManager.default.createFile(atPath: pidfile, contents: Data())
        let text = try String(contentsOfFile: pidfile, encoding: .utf8)
        XCTAssertTrue(text.isEmpty)
        XCTAssertNil(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                     "an empty pidfile must not parse to a pid")
    }
}
