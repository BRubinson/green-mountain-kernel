// swift-tools-version:6.0

// gmEagle — a kernel-side library, linked into the one `gm_kernel` Mach-O.
//
// Products:
//   - GmEagle (library)
//
// It floors at macOS 14 because the kernel does, and it must never inherit a
// consumer's floor: `gm_kernel` links this, and SwiftPM checks platform floors
// at graph resolution, so a 26 or 27 here would move `gm_hook`, `gm_daemon` and
// `gm_mcp` with it. It takes the `gmDaemonSdk` edge so its vocabulary IS the wire
// vocabulary, and no other — GRDB stays confined to `gmDaemon`, and this package
// adds no remote pin.

import PackageDescription

let package = Package(
    name: "gmEagle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmEagle", targets: ["GmEagle"])
    ],
    dependencies: [
        .package(path: "../API/Shared/GmKernelCoreShared")
    ],
    targets: [
        .target(
            name: "GmEagle",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "GmKernelCoreShared")
            ]
        )
    ]
)
