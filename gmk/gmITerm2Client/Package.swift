// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "gmITerm2Client",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "GmITerm2Client", targets: ["GmITerm2Client"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "GmITerm2Client",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
    ]
)
