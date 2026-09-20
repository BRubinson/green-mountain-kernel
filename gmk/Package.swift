// swift-tools-version:6.2

// gmk — the monolith kernel. One package, one product (`gm_kernel`), sections as targets.
//
// Floor: macOS 27 for everything, because `platforms` is package-wide and the
// agentics section needs the 27 SDK. The vendored ClaudeForFoundationModels stays
// a separate local package because it is upstream source, re-synced, never edited.

import PackageDescription

/// The settings the app code was written under; `gm_kernel` carries the app.
let appTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

/// The FoundationModels availability define, confined to the agentics section.
let gmAgentOs = SwiftSetting.unsafeFlags([
    "-Xfrontend", "-define-availability",
    "-Xfrontend", "GmAgentOs 1.0:macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0",
])

let package = Package(
    name: "gmk",
    platforms: [.macOS("27.0")],
    products: [
        // The one binary. daemon / mcp / hook by argv[0] or subcommand, bridge and app
        // by subcommand, and the app when launched from inside gm_kernel.app.
        .executable(name: "gm_kernel", targets: ["gm_kernel"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(path: "gmClaudeForFoundationModels"),
    ],
    targets: [
        // ── Base: wire protocol, client, shared domain ──────────────────────
        .target(
            name: "GmDaemonSdk",
            plugins: [.plugin(name: "StampVersion")]
        ),
        .target(name: "GmHookCli", dependencies: ["GmDaemonSdk"]),
        .target(name: "GmMcpServer", dependencies: ["GmDaemonSdk"]),

        // ── Persistence and the kernel host (the only GRDB consumer) ────────
        .target(
            name: "GmDaemon",
            dependencies: [
                "GmDaemonSdk",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "GmKernelHost",
            dependencies: ["GmDaemon", "GmMcpServer"],
            plugins: [.plugin(name: "StampBuildInfo")]
        ),

        // ── UI components ───────────────────────────────────────────────────
        .target(name: "GmUxComponentLibrary", dependencies: ["GmDaemonSdk"]),

        // ── Agentics: tool surface, templates, the plugin bridge ────────────
        .target(
            name: "GmAgententicsSdk",
            dependencies: [
                "GmDaemonSdk",
                .product(name: "ClaudeForFoundationModels", package: "gmClaudeForFoundationModels"),
            ],
            swiftSettings: [gmAgentOs]
        ),

        // ── iTerm2 transport (the only SwiftProtobuf consumer) ──────────────
        .target(
            name: "GmITerm2Client",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),

        // ── The kernel: dispatcher plus the app under Vibes/ ────────────────
        .executableTarget(
            name: "gm_kernel",
            dependencies: [
                "GmDaemonSdk", "GmHookCli", "GmMcpServer", "GmKernelHost",
                "GmUxComponentLibrary", "GmAgententicsSdk", "GmITerm2Client",
            ],
            swiftSettings: appTargetSettings
        ),

        // ── Build-time stamps ───────────────────────────────────────────────
        .plugin(name: "StampVersion", capability: .buildTool()),
        .plugin(name: "StampBuildInfo", capability: .buildTool()),

        // ── The one test suite ──────────────────────────────────────────────
        .testTarget(name: "GmKernelTests", dependencies: ["GmDaemonSdk", "GmDaemon"]),
    ]
)
