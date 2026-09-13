// swift-tools-version:6.0

// gmUxComponentLibrary — shared SwiftUI components. MIDDLE layer.
//
// SCOPE, as decided at clarification: **DiagramUI only, for now.** The user's
// words were "Diagram UI for now only, many things will be there later", so
// this is built as a real public component surface that EXPECTS TO GROW — but
// nothing else moves down in this prompt.
//
// Deliberately NOT moved here, and neither is an oversight:
//   - GMVibes `DesignSystem/` and `Markdown/` stay in the app.
//   - The two markdown renderers (`Markdown/MarkdownBlocksView.swift` here and
//     GMVibes' own `Markdown/`) are NOT reconciled. Merging them is a
//     behavioral change, not a move, and it does not belong in a reorg.
//
// Products:
//   - GmUxComponentLibrary (library)

import PackageDescription

let package = Package(
    name: "gmUxComponentLibrary",
    // macOS 14, DELIBERATELY NOT the app's deployment target of 26.1. A shared
    // component library that tracks one consumer's floor stops being shareable
    // the moment a second consumer appears — and the whole reason this package
    // exists is that more consumers are expected.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmUxComponentLibrary", targets: ["GmUxComponentLibrary"]),
    ],
    dependencies: [
        .package(path: "../gmDaemonSdk"),
    ],
    targets: [
        .target(
            name: "GmUxComponentLibrary",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
            ]
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
