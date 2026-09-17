// swift-tools-version:6.2
//
// The GMVibes app's code, as a package.
//
// Everything the app does lives here; `gmk/gmVibes/` is now a THIN app target
// holding only `GMVibesApp.swift` (the `@main` entry point, which must be in the
// app target), `Assets.xcassets` and its README.
//
// WHY THE SPLIT: sourcekit-lsp gets build settings for a Swift file only when
// that file belongs to a target it can see — SwiftPM, a compilation database, or
// BSP. It is NOT an Xcode client and reads neither `.xcworkspace` nor
// `.xcodeproj`. While these 104 sources lived only in an Xcode target, the
// language server had no settings for them and reported `No such module
// 'GmDaemonSdk'` on every import. Moving them into a package fixes that at the
// source, and does it without the `xcode-build-server` + `buildServer.json`
// machinery the alternative would have required.
//
// This package is a first-class member of `gmk/gmk.xcworkspace`, so it stays
// fully editable in Xcode and its test target gets a generated scheme.

import PackageDescription

/// The build settings the GMVibes APP TARGET already compiles under, restated
/// for SwiftPM.
///
/// These are not preferences — they are the app target's existing settings, and
/// the 99 sources in this package were written against them. `project.pbxproj`
/// carries `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_VERSION = 5.0`
/// on the GMVibes target; without both here the same source fails to build, e.g.
/// `actor-isolated default value in a main actor-isolated context` where a view
/// model's default value calls a `@MainActor` singleton.
///
/// If the app target's settings ever change, these must change with them. The
/// two halves compile the SAME code and disagreeing about isolation is a
/// difference that shows up as a wall of errors in one and silence in the other.
/// (`defaultIsolation` is why this manifest is swift-tools-version 6.2 while the
/// rest of the repo is on 6.0 — the setting does not exist before 6.2.)
let appTargetSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "gmVibesCore",
    // Matches the app target's MACOSX_DEPLOYMENT_TARGET. The string form rather
    // than `.v26` because that enum case requires swift-tools-version 6.4 and
    // every package in this repo is on 6.0.
    //
    // 26, NOT 27, AND THAT IS LOAD-BEARING. The app used to floor at 27 and this
    // package matched it — but nothing in these sources ever needed 27. The floor
    // came in sideways: the GMVibes target linked GmAgententicsSdk, which depends
    // on the vendored gmClaudeForFoundationModels, and BOTH floor at 27. SwiftPM
    // checks platform floors at GRAPH RESOLUTION, so that one link pinned the
    // whole app. Nothing imported it. The link is gone from project.pbxproj and
    // the floor came down with it.
    //
    // Verified rather than assumed: building this package at 26 succeeds with
    // zero errors, and a macOS 26 build of the GMVibes scheme failed ONLY inside
    // ClaudeForFoundationModels before that link was cut.
    //
    // Do not lower it further. There is no requirement to, and a lower number
    // would widen the support claim to OS versions nobody has built against.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GmVibesCore", targets: ["GmVibesCore"])
    ],
    dependencies: [
        // FOUR. This was TWO, with a note explaining that nothing imported
        // GmDaemon and that the app target's GmKernelHost link existed only for
        // "future writer hosting". THAT FUTURE IS NOW: `GMVibesServices`
        // arbitrates database ownership and hosts the writer in-process, so it
        // imports GmKernelHost and the edge belongs here.
        //
        // The edge is safe in both directions that matter. Nothing under
        // gmDaemon depends on this package, so the graph stays acyclic. And
        // gmDaemon's platform floor (macOS 14) is BELOW this package's 26, so
        // adding it moves no floor — the opposite of the gmAgententicsSdk case,
        // where a macOS 27 dependency pinned the whole app at graph resolution.
        // Do not confuse the two: floors propagate UPWARD to consumers, and
        // this consumer is already higher.
        //
        // The FOURTH is gmITerm2Client — the iTerm2 transport, and what
        // `PromptRunBar`'s Play button launches through. It brings the tree's
        // first remote non-GRDB pin (SwiftProtobuf), confined to that package
        // exactly as GRDB is confined to gmDaemon: nothing generated crosses
        // its actor boundary, so gmVibesCore never imports SwiftProtobuf. IT
        // MOVES NO FLOOR EITHER — gmITerm2Client declares macOS 26 (it was 27,
        // lowered in the same commit as this line, because 27 was never earned
        // there), which is exactly this package's floor rather than above it.
        .package(path: "../gmDaemonSdk"),
        .package(path: "../gmUxComponentLibrary"),
        .package(path: "../gmDaemon"),
        .package(path: "../gmITerm2Client"),
    ],
    targets: [
        .target(
            name: "GmVibesCore",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(name: "GmUxComponentLibrary", package: "gmUxComponentLibrary"),
                .product(name: "GmKernelHost", package: "gmDaemon"),
                .product(name: "GmITerm2Client", package: "gmITerm2Client"),
            ],
            swiftSettings: appTargetSettings
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
