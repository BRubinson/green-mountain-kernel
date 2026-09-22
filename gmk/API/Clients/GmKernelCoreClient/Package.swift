// swift-tools-version:6.0

// GmKernelCoreClient — the harness-side CLIENTS of the kernel, in one package.
//
// Products:
//   - GmKernelClient (library)    the NDJSON unix-socket transport (`DaemonClient`),
//                                 event streaming, and the client-side context
//                                 resolvers built on it
//   - GmHookCli      (library)    the `gm_hook` shell-client personality
//   - GmMcpServer    (library)    the `gm_mcp` pen server personality
//   - gm_hook        (executable) a shim over GmHookCli.main()
//
// Every target here is a pure relay with no persistence of its own, floors at
// macOS 14, and links the shared SDK alone. GRDB is named by exactly one
// manifest (the server package); nothing here pulls it, so `gm_hook` and
// `gm_mcp` never carry the Store in their link closure.
//
// The socket conformance `DaemonClient: GmVerbCaller` lives here rather than in
// the SDK: the protocol and its ~110 typed verbs are shared, the socket that
// satisfies them is a client concern.

import PackageDescription

let package = Package(
    name: "GmKernelCoreClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmKernelClient", targets: ["GmKernelClient"]),
        .library(name: "GmHookCli", targets: ["GmHookCli"]),
        .library(name: "GmMcpServer", targets: ["GmMcpServer"]),
        .executable(name: "gm_hook", targets: ["gm_hook"]),
    ],
    dependencies: [
        .package(path: "../../Shared/GmKernelCoreShared")
    ],
    targets: [
        .target(
            name: "GmKernelClient",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "GmKernelCoreShared")
            ]
        ),
        // NO ArgumentParser: a dozen ops verbs plus a raw passthrough, parsed
        // by hand.
        .target(
            name: "GmHookCli",
            dependencies: [
                "GmKernelClient",
                .product(name: "GmDaemonSdk", package: "GmKernelCoreShared"),
            ]
        ),
        .target(
            name: "GmMcpServer",
            dependencies: [
                "GmKernelClient",
                .product(name: "GmDaemonSdk", package: "GmKernelCoreShared"),
            ]
        ),
        // A real executable target so `swift build` still yields a standalone
        // `gm_hook` for the release store to stage.
        .executableTarget(
            name: "gm_hook",
            dependencies: ["GmHookCli"]
        ),
    ]
)
