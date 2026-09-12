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
        .testTarget(
            name: "GmUxComponentLibraryTests",
            dependencies: ["GmUxComponentLibrary"]
        ),
    ]
)
