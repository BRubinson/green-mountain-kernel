// swift-tools-version:6.0

// gmMcp — the MCP stdio server: the agent PEN surface as typed MCP tools.
//
// The cleanest carve of the six. Three files, hand-rolled JSON-RPC
// (initialize / tools/list / tools/call), and a THIRD thin client of the daemon
// socket — never a second writer to the database.
//
// Products:
//   - GmMcpServer (library)    the pen server, so the one multi-call
//                              `gm_kernel` Mach-O can serve it
//   - gm_mcp      (executable) a shim over GmMcpServer.main()
//
// THE LIBRARY SPLIT CHANGES NO BEHAVIOUR. `gm_mcp` is still spawned per Claude
// session by the harness, still speaks stdio, still never touches the db. The
// split exists because top-level code is legal only in an executable's
// `main.swift`, and the kernel binary needs this personality as a callable
// entry point.

import PackageDescription

let package = Package(
    name: "gmMcp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmMcpServer", targets: ["GmMcpServer"]),
        .executable(name: "gm_mcp", targets: ["gm_mcp"]),
    ],
    dependencies: [
        // gmDaemonSdk ALONE. Verified before the split: this code never reaches
        // `Database/`. It talks to the daemon over the socket like any other
        // client, which is exactly why it must not link persistence — a second
        // process holding the Store would break the single-writer guarantee the
        // whole design rests on.
        .package(path: "../gmDaemonSdk"),
        // TEST TARGET ONLY. `gm_mcp` itself must never link persistence — a
        // second process holding the Store would break the single-writer
        // guarantee. But PenResultNarrowingTests needs a REAL database to
        // build the oversize architecture payload it narrows, and a hand-rolled
        // stub would not reproduce the bug this file exists for (a 79,598-char
        // arch_get refused by the harness and returned cut mid-array). SwiftPM
        // cannot scope a dependency to a test target, so the edge shows here.
        .package(path: "../gmDaemon"),
    ],
    targets: [
        .target(
            name: "GmMcpServer",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
            ]
        ),
        // A shim over GmMcpServer.main(). Kept as a real executable target so
        // `swift build` still yields a standalone `gm_mcp` — `run_mcp.sh` execs
        // that path by name, and the release store stages it.
        .executableTarget(
            name: "gm_mcp",
            dependencies: ["GmMcpServer"]
        ),
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
