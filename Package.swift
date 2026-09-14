// swift-tools-version: 6.0
//
// LSP SHIM — THIS PACKAGE SHIPS NOTHING AND BUILDS NOTHING OF ITS OWN.
//
// It exists for exactly one reason: `sourcekit-lsp` picks its build system by
// looking for `Package.swift` / `buildServer.json` / `compile_commands.json` AT
// THE WORKSPACE ROOT, and it does NOT search downward. The Claude Code
// `swift-lsp` plugin launches the server rooted at the repo root with no
// arguments, so without a manifest HERE the server attaches no language service
// to any Swift file in this repo and every request fails
// `No language service found`.
//
// Declaring the eight real packages as path dependencies puts them all in one
// resolved graph that the language server can answer from. Nothing else in the
// repo reads this file: the build and release path is `gmk/scripts/`, CI drives
// the packages individually, and `gmk/` remains the one home for every Swift
// deliverable. Do not add targets or products here.

import PackageDescription

let package = Package(
    name: "gmk-lsp-workspace",
    // macOS 27 because `gmAgententicsSdk` depends on the vendored
    // `gmClaudeForFoundationModels`, whose floor is 27, and SwiftPM checks
    // floors at GRAPH RESOLUTION. A consumer may sit above its dependencies but
    // never below one, so the umbrella takes the highest floor in the graph.
    // The string form, not `.v27`, matching `gmAgententicsSdk` — the enum case
    // requires swift-tools-version 6.4 and every package here is on 6.0.
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "gmk/gmDaemonSdk"),
        .package(path: "gmk/gmDaemon"),
        .package(path: "gmk/gmUxComponentLibrary"),
        // gmk/gmMcp is GONE (v30). Its three sources are the GmMcpServer target
        // inside gmDaemonSdk now, so they are still reachable from here through
        // the entry above — which is what keeps the language server resolving
        // them. A stale path here is worse than a missing one: manifest
        // resolution fails for the WHOLE graph, so every file in the repo loses
        // code intelligence at once, and it does so QUIETLY, because a server
        // with no language service still publishes clean diagnostics.
        .package(path: "gmk/Gm_Kernel_test"),
        .package(path: "gmk/gmKernel"),
        .package(path: "gmk/gmAgententicsSdk"),
        .package(path: "gmk/gmClaudeForFoundationModels"),
        .package(path: "gmk/gmVibesCore"),
    ]
)
