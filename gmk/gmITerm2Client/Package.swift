// swift-tools-version:6.0
//
// The iTerm2 transport. One unix socket, one WebSocket handshake, one protobuf
// verb — and nothing that knows what GMCC is.
//
// THE TREE'S SECOND REMOTE PIN, AND THE FIRST NON-GRDB ONE. SwiftProtobuf is
// confined here exactly as GRDB is confined to `gmDaemon`. A SwiftProtobuf pin
// appearing in any other manifest in this repo means the transport has leaked
// upward — the actor is supposed to speak only the Sendable value types this
// package defines, so nothing above it has any reason to know protobuf exists.
//
// DO NOT ADD `.defaultIsolation(MainActor.self)`, AND DO NOT COPY
// `gmVibesCore`'s `appTargetSettings` HERE. That setting is gmVibesCore's, and
// it is there only because it restates what the GMVibes *app target* already
// compiles under. Copying it into this manifest would make the transport's
// non-isolated halves — `SocketConnection`, `WebSocketClient`, `APIClient`,
// and the actor that owns them — MainActor-isolated, and would therefore
// SILENTLY REINTRODUCE MAIN-THREAD BLOCKING ON A SOCKET READ. `recv` blocks
// under a 30-second timeout. Keeping that off the main thread is the entire
// reason this package exists as its own compilation unit.

import PackageDescription

let package = Package(
    name: "gmITerm2Client",
    // Matches every other package in the tree. The string form rather than
    // `.v27` because that enum case requires swift-tools-version 6.4 and this
    // repo is on 6.0.
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
        // NO TEST TARGET. The repository has ONE test package
        // (`gmk/Gm_Kernel_test`) and nothing in this slice is reachable from
        // it — it boots a kernel, not a terminal. Correctness here comes from
        // structure: the transport classes are non-Sendable on purpose, so
        // Swift 6 makes escaping one a compile error, and `ITerm2Error` is a
        // closed enum a caller must switch over exhaustively.
    ]
)
