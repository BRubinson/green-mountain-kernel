// swift-tools-version:6.0

// gmMcp — the MCP stdio server: the agent PEN surface as typed MCP tools.
//
// The cleanest carve of the six. Three files, hand-rolled JSON-RPC
// (initialize / tools/list / tools/call), and a THIRD thin client of the daemon
// socket — never a second writer to the database.
//
// Products:
//   - gm_mcp (executable)

import PackageDescription

let package = Package(
    name: "gmMcp",
    platforms: [.macOS(.v14)],
    products: [
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
        .executableTarget(
            name: "gm_mcp",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
            ]
        ),
        .testTarget(
            name: "GmMcpTests",
            dependencies: [
                "gm_mcp",
                .product(name: "GmDaemon", package: "gmDaemon"),
            ]
        ),
    ]
)
