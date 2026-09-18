// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "gmITerm2Client",
    // 26, NOT 27, AND THE DIRECTION OF THE FIX IS LOAD-BEARING.
    //
    // 27 was never EARNED here. There is not a single `@available` anywhere in
    // `Sources/` (excluding the generated protobuf), and the import set is
    // AppKit, Foundation, FoundationEssentials, Security and SwiftProtobuf —
    // SwiftProtobuf itself supports macOS 10.15+. The floor was copied from
    // whatever gmVibesCore happened to be when this package was written.
    //
    // 26 is VERIFIED BY BUILD, not by source scan: three independent lenses
    // built this package green at 26 — `Build complete! (10.95 sec)` /
    // `(11.18 sec)` / `(11.28 sec)`, zero warnings, SwiftProtobuf resolved and
    // compiled.
    //
    // DO NOT FIX THIS THE OTHER WAY. Raising gmVibesCore and the three
    // `MACOSX_DEPLOYMENT_TARGET = 26.0` rows back to 27 reverses a deliberate,
    // empirically verified floor cut that `gmVibesCore/Package.swift:49-62`
    // defends in three paragraphs. And do not lower it further: 26 matches the
    // consumer, and lower widens the support claim to OS versions nobody has
    // built against.
    //
    // WHERE THE FAILURE LANDS, because the symptom is mislabelled elsewhere.
    // CLAUDE.md says SwiftPM checks floors "at GRAPH RESOLUTION". With a floor
    // above the consumer's, RESOLUTION SUCCEEDS (swift-protobuf 1.38.1 fetches
    // fine) and the failure lands at build PLANNING:
    //     error: The package product 'GmITerm2Client-product' requires minimum
    //     platform version 27.0 for the macOS platform, but this target
    //     supports 26.0
    // Someone watching for a resolution error will not recognise a planning
    // error, and `@available` cannot reach either.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GmITerm2Client", targets: ["GmITerm2Client"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0")
    ],
    targets: [
        .target(
            name: "GmITerm2Client",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ]
        )
    ]
)
