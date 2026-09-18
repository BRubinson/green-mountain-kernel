// swift-tools-version:6.0

// gmKernel — the multi-call binary. ONE Mach-O that answers as three.
//
// Products:
//   - gm_kernel (executable)
//
// ── WHY THIS IS A PACKAGE OF ITS OWN ────────────────────────────────────────
//
// The three personalities ship from three different packages: the hook CLI from
// gmDaemonSdk, the pen server from gmMcp, the kernel host from gmDaemon. An
// executable that links all three has to live somewhere that can depend on all
// three, and no existing package can.
//
// gmMcp looked like the obvious home — it already has an edge on gmDaemon. But
// that edge is TEST-ONLY, and SwiftPM cannot scope a dependency to a test target,
// so it is declared at package level while no shipped target uses it. Putting a
// SHIPPED executable there that links GmKernelHost would drag GRDB into gmMcp's
// shipped graph and break the invariant that manifest is built around: `gm_mcp`
// never links persistence, because a second process holding the Store would break
// single-writer. One extra manifest is cheaper than that.
//
// Cost, stated plainly: +1 CI matrix row and +1 entry in
// `RepoRoot.sourcePackages`. Both are one-line edits; the alternative was a
// documented invariant becoming false.
//
// ── WHY ONE BINARY RATHER THAN THREE RENAMED ONES ───────────────────────────
//
// The rename could have produced `gm_kernel`, `gm_kernel_mcp` and
// `gm_kernel_hook`. Collapsing to one Mach-O with argv[0] dispatch — the pattern
// Tailscale, Docker and VS Code use — is both closer to the goal ("the kernel
// should expose ALL parts") and cheaper: every command string in `hooks.json`,
// `settings.json` and `.mcp.json` keeps resolving, because `~/gmfs/bin/gm_mcp`
// and `~/gmfs/bin/gm_hook` become SYMLINKS at this binary rather than paths that
// stopped existing. `DocsContractTests.assertScriptIsLaunchable` therefore stays
// green by construction instead of by a manifest edit.
//
// The symlink NAMES are consequently load-bearing. A staged kernel whose entry
// symlinks are missing is not a degraded install — it is a hook that cannot
// launch at all.

import PackageDescription

let package = Package(
    name: "gmKernel",
    // macOS 14, NOT the app's floor. This package links no agentics code and no
    // SwiftUI, so it must not inherit a consumer's platform requirement — the
    // same rule gmDaemonSdk's manifest states for the same reason.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gm_kernel", targets: ["gm_kernel"])
    ],
    dependencies: [
        .package(path: "../gmDaemonSdk"),
        .package(path: "../gmDaemon"),
    ],
    targets: [
        .executableTarget(
            name: "gm_kernel",
            dependencies: [
                .product(name: "GmKernelHost", package: "gmDaemon"),
                .product(name: "GmMcpServer", package: "gmDaemonSdk"),
                .product(name: "GmHookCli", package: "gmDaemonSdk"),
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
            ]
        )
    ]
)
