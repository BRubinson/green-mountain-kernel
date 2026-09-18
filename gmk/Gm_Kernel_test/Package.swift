// swift-tools-version:6.0

// Gm_Kernel_test — the repository's ONE test package.
//
// Replaces seven per-package test targets (647 cases, ~19,000 lines) with a
// single suite that boots ONE shared environment per test process and exercises
// the whole daemon kit through its PUBLIC surface: the wire protocol, a real
// `gm_kernel` over a real socket, and read-only SQL against the database that
// kernel owns.
//
// ── WHY ONE SHARED ENVIRONMENT, AND WHY IT IS THE ONLY SHAPE AVAILABLE ───────
//
// `Paths.root` is a `static let`. One root per PROCESS, forever — a per-suite
// or per-test root cannot take effect, and a design that assumes otherwise
// fails in the most confusing way possible: silently, against whatever root the
// process resolved first. So "one shared environment" is not merely the ask; it
// is the only shape the type permits. Say this out loud in any harness change.
//
// ── ISOLATION IS BY CONSTRUCTION, NOT BY A GUARD ─────────────────────────────
//
// The guard that used to prove tests never touch the live runtime
// (`LiveRuntimeIsolationTests`) was deleted along with the rest of the old
// suite, deliberately and on the record. What replaced it is stronger than a
// scan, because it is structural rather than observational:
//
//   - the harness MINTS a root under NSTemporaryDirectory() and string-appends
//     every path beneath it. It never calls `Paths.*` to DISCOVER a path, so
//     there is no expression here that can resolve the installed runtime.
//   - it WRITES `GM_FS_ROOT` into the environment of the CHILD it spawns.
//     Writing is not reading; this process never consults the variable.
//   - it reaches the daemon through the already-existing
//     `DaemonClient(socketPath:daemonBinaryPath:autostart:)` parameters, so
//     nothing in production had to change to make this testable.
//
// ── DB ACCESS IS READ-ONLY, AND THAT IS A CORRECTNESS RULE ───────────────────
//
// The suite boots a real kernel, which takes the `flock` and owns `gm.db` as
// sole writer. A test-side `Store(path:)` against that same database would be
// the SECOND WRITER the entire ownership-token design exists to make
// inexpressible — reintroduced inside the tests that are supposed to defend it.
// Every query here opens a read-only `DatabaseQueue`. Writes go over the wire,
// like any other client's.
//
// ── XCTest, NOT swift-testing ────────────────────────────────────────────────
//
// swift-testing parallelises by default, and a single shared append-only
// database does not survive that. XCTest also has `XCTestObservation`, which
// gives real once-per-PROCESS setup *and* teardown — the teardown half matters,
// because something has to reap a spawned kernel and delete a temp root even
// when a test fails.
//
// ── ORGANISATION ─────────────────────────────────────────────────────────────
//
// One subfolder per package under Tests/GmKernelTests/, so a reader looking for
// "the daemon's tests" finds them where they expect. They share the one
// environment; the folders are for navigation, not isolation.
//
// ── COSTS, ACCEPTED IN WRITING ───────────────────────────────────────────────
//
//   - macOS 14 floor here, deliberately the LOWEST that still works: this
//     package links no agentics code, so it must not inherit the app's 27.
//   - The 8-row CI matrix collapses to one job. Mitigate with `--filter` rows
//     rather than by re-splitting the package.
//   - Test independence is gone. Cases must be order-independent by
//     UNIQUENESS — every fixture names itself — rather than by isolation.

import PackageDescription

let package = Package(
    name: "Gm_Kernel_test",
    // The lowest floor that compiles. Matches gmToolchain's rule and for the
    // same reason: a test package must never be why a CI job needs a newer SDK.
    platforms: [.macOS(.v14)],
    // Ships NOTHING. Like gmToolchain before it, this package exists to be run,
    // never to be linked.
    products: [],
    dependencies: [
        // The wire vocabulary and the client. This is the PUBLIC surface the
        // suite is written against.
        .package(path: "../gmDaemonSdk"),
        // For `Migrations` ONLY — which is public, and which the migration
        // ladder drives over its own in-memory database. NOT for `Store`:
        // constructing one here is the second-writer bug above.
        .package(path: "../gmDaemon"),
    ],
    targets: [
        .testTarget(
            name: "GmKernelTests",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(name: "GmDaemon", package: "gmDaemon"),
            ]
        )
    ]
)
