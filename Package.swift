// swift-tools-version: 6.2
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
// Declaring the one gmk package as a path dependency puts its whole graph (the
// vendored ClaudeForFoundationModels included) in one resolved graph the
// language server can answer from. Nothing else in the repo reads this file:
// the build and release path is `gmk/scripts/`. Do not add targets or products
// here.

import PackageDescription

let package = Package(
    name: "gmk-lsp-workspace",
    // The gmk package floors at macOS 27; a consumer may not sit below one.
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "gmk")
    ]
)
