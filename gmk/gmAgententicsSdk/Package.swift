// swift-tools-version:6.0

// gmAgententicsSdk — the agent-tool surface. BASE layer, independent of
// gmDaemonSdk.
//
// SIXTY LINES OF PROTOCOL DECLARATIONS, and it is meant to stay that way for
// now. The prompt that created this package forbids fleshing it out in so many
// words. Its emptiness is a decision, not a gap, and its CI job is
// compile-only because zero tests exist to run. Nobody should read the empty
// test target below as a TODO.
//
// Products:
//   - GmAgententicsSdk (library)

import PackageDescription

// The FoundationModels availability floor, defined once.
//
// ISOLATING THIS HERE IS A REAL STRUCTURAL GAIN, worth naming rather than
// leaving implicit: in the old monolith this setting was applied to the WHOLE
// kit target, so every file in 15k loc compiled under an unsafe flag for the
// sake of one 60-line file. Confined to this package, every other module in
// the graph is flag-free.
//
// THE PERMANENT COST, stated here rather than discovered later: `unsafeFlags`
// bars a package from being consumed as a VERSIONED REMOTE dependency. All six
// gmk packages are local `path:` dependencies, so this is free today — but it
// means this package can only ever be consumed by local path. Publishing it
// would require replacing this flag first.
let gmAgentOs = SwiftSetting.unsafeFlags([
    "-Xfrontend", "-define-availability",
    "-Xfrontend", "GmAgentOs 1.0:macOS 27.0, iOS 27.0, visionOS 27.0, watchOS 27.0",
])

let package = Package(
    name: "gmAgententicsSdk",
    // macOS 26, made EXPLICIT rather than inherited from a neighbour.
    // `GmAgentTool.swift` imports FoundationModels UNCONDITIONALLY, and that
    // framework exists only in the macOS 26 SDK. An older SDK does not
    // degrade gracefully — the package does not compile at all. Any CI job
    // whose graph transitively includes this package inherits the floor, which
    // is why the workflows pin macos-26.
    // Spelled as a STRING, not `.macOS(.v26)`: the `.v26` case does not exist
    // in every SwiftPM version that can build this repo, and a manifest that
    // fails to PARSE is a worse failure than one that fails to compile — it
    // takes the whole package graph down with it.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GmAgententicsSdk", targets: ["GmAgententicsSdk"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "GmAgententicsSdk",
            swiftSettings: [gmAgentOs]
        ),
        // Empty by design — see the header. Declared so the target exists and
        // the CI matrix has a uniform shape across all six packages.
        .testTarget(
            name: "GmAgententicsSdkTests",
            dependencies: ["GmAgententicsSdk"],
            swiftSettings: [gmAgentOs]
        ),
    ]
)
