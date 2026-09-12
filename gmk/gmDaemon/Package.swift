// swift-tools-version:6.0

// gmDaemon — persistence and the single-writer server. MIDDLE layer.
//
// Holds `Database/` (the Store, its repositories, and the append-only
// migration ledger) plus `gm_daemon`, the server that owns the database file.
//
// Products:
//   - GmDaemon  (library)    the Store surface
//   - gm_daemon (executable) the single-writer daemon
//
// THE APP DOES NOT LINK THIS, and that is the structural win of the split. The
// old monolith made every GMVibes build carry GRDB because one target held both
// the wire types and the Store. Measured before the split: GMVibes had zero
// references to GRDB, `GMCCStore`, `DatabaseQueue` or `StoreError` across 97
// files — it never wanted persistence, it merely inherited it.

import PackageDescription

let package = Package(
    name: "gmDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmDaemon", targets: ["GmDaemon"]),
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
        // The plugin is on THIS target, not on the library: BuildInfo is what
        // the PING handler reports, and the handler lives here.
        .executableTarget(
            name: "gm_daemon",
            dependencies: ["GmDaemon"],
            plugins: [.plugin(name: "StampBuildInfo")]
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
        .testTarget(
            name: "GmDaemonTests",
            dependencies: [
                "GmDaemon",
                .product(name: "GmUxComponentLibrary", package: "gmUxComponentLibrary"),
            ]
        ),
    ]
)
