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
    // than `.v27` because that enum case requires swift-tools-version 6.4 and
    // every package in this repo is on 6.0.
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "GmVibesCore", targets: ["GmVibesCore"])
    ],
    dependencies: [
        // EXACTLY TWO, established by counting every import under the old
        // gmk/gmVibes/: 67 files import GmDaemonSdk, 17 import
        // GmUxComponentLibrary, and NOTHING imports GmDaemon.
        //
        // That last point is not an oversight to be corrected: the app target
        // links GmKernelHost for future writer hosting but does not import it,
        // exactly as CLAUDE.md records. The link stays on the APP target — moving
        // it here would quietly misrepresent the documented "the app does not
        // host the writer yet" state.
        .package(path: "../gmDaemonSdk"),
        .package(path: "../gmUxComponentLibrary"),
        .package(path: "../gmITerm2Client"),
    ],
    targets: [
        .target(
            name: "GmVibesCore",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(name: "GmUxComponentLibrary", package: "gmUxComponentLibrary"),
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
