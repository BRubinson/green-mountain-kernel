// swift-tools-version:6.0

// gmToolchainTests — the SEVENTH package, and the only one that ships nothing.
//
// THE TESTS THAT READ FILES RATHER THAN CALL SYMBOLS. That is the whole
// membership rule, and it is what makes this a coherent package instead of a
// leftovers bin:
//
//   - DocsContractTests      asserts on plugins/gmcc/ markdown, hooks.json,
//                            settings.json, .mcp.json and the launcher scripts
//   - HookScriptTests        runs the real hook launcher in a scrubbed sandbox
//   - WorkflowSpecTests      reads gm_mcp's SOURCE TEXT and checks the served
//                            pen roster against the registry, bidirectionally
//   - LiveRuntimeIsolationTests  scans every package's Tests/ tree and refuses
//                            a test that resolves the installed runtime
//
// None of them belongs to a module, because none of them tests a module's
// internals — they test the repository. Filing them under whichever package
// happened to be nearby is how a test ends up asserting about a tree it has no
// relationship to, and how a doc-contract walk ends up silently examining zero
// files after a directory moves.
//
// It also owns `RepoRoot`, the ONE #filePath-to-repo-root resolver. Four test
// files used to re-derive the root by counting directories; the count encoded
// their depth and every one of them broke when the package moved.
//
// WHY RepoRoot IS A TARGET SOURCE AND NOT A LIBRARY PRODUCT: it started as a
// product so other packages' test targets could import it, which made
// gmDaemonSdk depend on this package — while this package needs gmDaemonSdk for
// `DopeVocabulary.retiredAcronym` (read from the SDK on purpose, so the docs
// contract cannot drift from the canonical vocabulary). That is a CYCLE, and
// SwiftPM rejects it. Collecting the file-scanning tests here instead leaves a
// single dependency edge pointing one way, and the helper has exactly one
// consumer: this target.
//
// NOT a shipped module. Nothing in gmk/'s runtime graph depends on it, and
// nothing should.

import PackageDescription

let package = Package(
    name: "gmToolchainTests",
    // The lowest floor in the graph. These tests parse files and run `bash -n`;
    // this package must never be the reason a CI job needs a newer SDK.
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        // ONE edge, and it points DOWN. Used for the canonical vocabulary
        // constants the docs contract asserts against — not for internals:
        // these tests take the SDK as a plain `import`, never `@testable`.
        .package(path: "../gmDaemonSdk"),
    ],
    targets: [
        .testTarget(
            name: "GmToolchainTests",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
            ]
        ),
    ]
)
