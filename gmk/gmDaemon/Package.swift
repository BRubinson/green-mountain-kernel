// swift-tools-version:6.0

// gmDaemon — persistence and the single-writer server. MIDDLE layer.
//
// Holds `Database/` (the Store, its repositories, and the append-only
// migration ledger) plus `gm_daemon`, the server that owns the database file.
//
// Products:
//   - GmDaemon      (library)    the Store surface
//   - GmKernelHost  (library)    the server + the ownership primitives, so the
//                                app bundle and the headless binary are two
//                                HOSTS over ONE implementation
//   - gm_daemon     (executable) a shim over KernelHost.bootHeadlessAndRun()
//
// THE APP NOW LINKS THIS, AND THAT REVERSES THE PREVIOUS HEADER ON PURPOSE.
//
// What this file used to say: "THE APP DOES NOT LINK THIS, and that is the
// structural win of the split" — measured at zero references to GRDB,
// `DatabaseQueue` or `StoreError` across 97 GMVibes files. That was true and it
// was worth having. It is now deliberately false, and the sentence is kept
// (corrected, not deleted) so the change reads as a decision rather than a
// regression someone should undo.
//
// The reason is that the collapse asked for ONE connection pool and REAL shared
// transaction boundaries across the UI, the relayed MCP surface and the kernel's
// own background services. A process boundary cannot provide a shared
// transaction: every wire call is its own. So the app hosts the writer, and the
// cost is exactly the one the old header was protecting against — GRDB is in the
// app's link closure again.
//
// What keeps that from being a regression is that the guarantee it protected got
// STRONGER rather than weaker. Single-writer used to mean "only this executable
// constructs a Store". It now means "only the holder of the ownership lock can
// construct one", enforced by a `~Copyable` token whose initialiser no other file
// can reach. See `KernelOwnership`.

import PackageDescription

let package = Package(
    name: "gmDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmDaemon", targets: ["GmDaemon"]),
        .library(name: "GmKernelHost", targets: ["GmKernelHost"]),
        .executable(name: "gm_daemon", targets: ["gm_daemon"]),
    ],
    dependencies: [
        .package(path: "../gmDaemonSdk"),
        // THE SOLE GRDB PIN, and the only manifest in this repo permitted to
        // name it. Measured: GRDB is imported by 96 of the 100 files in
        // `Database/` and by nothing anywhere else. A pin in any other manifest
        // would be a sign that persistence had leaked upward.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // TEST TARGET ONLY — see GmDaemonTests below. SwiftPM has no
        // test-scoped dependency, so this edge is visible in the manifest even
        // though no shipped target may use it. GmDaemon itself must NEVER
        // import a UI component library.
        .package(path: "../gmUxComponentLibrary"),
    ],
    targets: [
        .target(
            name: "GmDaemon",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // The server, the handlers, the watchers, and the ownership primitives.
        //
        // THE BUILD PLUGIN MOVED HERE WITH PingHandler. BuildInfo is what PING
        // reports, and the handler that reports it is in this target now — a
        // plugin left on the executable would have stamped a target that no
        // longer contains the reader.
        .target(
            name: "GmKernelHost",
            dependencies: ["GmDaemon"],
            plugins: [.plugin(name: "StampBuildInfo")]
        ),
        // A shim over KernelHost.bootHeadlessAndRun(). Kept as a real executable
        // target because the headless writer is load-bearing: autostart spawns a
        // binary from contexts that cannot launch an app.
        .executableTarget(
            name: "gm_daemon",
            dependencies: ["GmKernelHost"]
        ),
        // The build-time stamp, inside the build graph. See the plugin's own
        // source for why this replaced a shell step.
        .plugin(
            name: "StampBuildInfo",
            capability: .buildTool()
        ),
        // The gmUxComponentLibrary dependency is for exactly ONE test:
        // `testDopeCanvasLayoutScaffoldsIdenticallyThroughBothPaths`, a
        // DIFFERENTIAL ORACLE that runs the scaffold mutations GMVibes
        // generates through the reducer and through the daemon and demands the
        // same tree. It spans both sides by construction — that parity IS the
        // thing under test — so it has to see both modules. A test that can
        // only see one of two paths cannot compare them.
        // TEST TARGET REMOVED. The repository's tests live in ONE package now,
        // gmk/Gm_Kernel_test, which boots a shared environment and drives the
        // whole kit through its PUBLIC surface plus read-only SQL.
        //
        // This was a deliberate clean break, not attrition: ~647 cases across
        // seven targets were deleted in one commit, including ten repository
        // contract tests whose invariants are now unenforced. That cost was
        // weighed and accepted rather than discovered. Do not re-add a test
        // target here — a second home is how the suite fragmented last time.
    ]
)
