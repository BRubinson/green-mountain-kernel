// VENDORED THIRD-PARTY SOURCE — DO NOT EDIT BY HAND.
//
//   upstream: https://github.com/anthropics/ClaudeForFoundationModels
//   commit:   5a0fde3ae4275c3ae7ebf840bea840af268138c2
//   version:  0.2.0  (tagged 2026-09-09)
//   license:  Apache-2.0 — see the LICENSE file beside this one
//
// This block is the ONLY local modification to the upstream tree; every other
// file under this directory is byte-identical to that commit. Re-sync, and the
// reason this is a local copy rather than a `.package(url:)` pin, are both in
// VENDORED.md.
//
// ─────────────────────────────────────────────────────────────────────────────
//
// Copyright 2026 Anthropic PBC
// SPDX-License-Identifier: Apache-2.0

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ClaudeForFoundationModels",
  // Every OS where Foundation Models supports server-side language models.
  // Spelled as strings because the .v27 constants require tools-version 6.4.
  platforms: [
    .iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0"),
  ],
  products: [
    .library(name: "ClaudeForFoundationModels", targets: ["ClaudeForFoundationModels"])
  ],
  targets: [
    // Internal Messages API client. No FoundationModels dependency.
    .target(name: "ClaudeAPI"),

    // FoundationModels ↔ Messages API bridge.
    .target(
      name: "ClaudeForFoundationModels",
      dependencies: ["ClaudeAPI"]
    ),

    // Runnable usage example (`swift run ClaudeExample`). Deliberately not a
    // product — it exists to document the SDK, not to be depended on.
    .executableTarget(
      name: "ClaudeExample",
      dependencies: ["ClaudeForFoundationModels"],
      path: "Examples/ClaudeExample"
    ),

    .testTarget(
      name: "ClaudeAPITests",
      dependencies: ["ClaudeAPI"]
    ),
    .testTarget(
      name: "ClaudeForFoundationModelsTests",
      dependencies: ["ClaudeForFoundationModels"]
    ),
  ]
)
