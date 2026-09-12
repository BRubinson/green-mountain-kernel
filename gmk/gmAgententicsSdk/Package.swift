// swift-tools-version:6.0

// gmAgententicsSdk — the agent-tool surface: the seven GmAgentTool families
// declared against Apple's FoundationModels `Tool` protocol, with @Generable
// argument and result schemas.
//
// NO LONGER THE GRAPH'S ISLAND, and that is the one thing to know before
// reading further. This package declared `dependencies: []` for its whole life
// and CLAUDE.md drew it standing alone. It now depends on gmDaemonSdk, because
// every tool schema here speaks the daemon's vocabulary — ExplorationFindingKind,
// ReviewFindingKind, SearchKind, DopeSearchScope, ReviewVerdict, PromptStatus.
// The alternative was a hand-maintained second copy of a dozen enums whose raw
// values are load-bearing on the wire AND in db CHECK constraints, which is the
// exact failure mode three separate contract tests in this repo already exist to
// prevent. Sharing the type is what makes drift impossible rather than merely
// discouraged.
//
// The edge is safe in both directions worth checking: it cannot cycle, because
// nothing in the repo depends on THIS package; and gmDaemonSdk does not inherit
// the unsafeFlags below, because SwiftPM target settings apply only to the
// target that declares them.
//
// AN EARLIER DECISION, NOW RETIRED. This header used to say the package was
// sixty lines of protocol declarations "meant to stay that way", that the prompt
// which created it forbade fleshing it out, and that its emptiness was a
// decision rather than a gap. All of that was true and is no longer: the prompt
// that filled the package is the successor decision. The sentence is kept in
// this form — naming what changed — rather than deleted, so a reader who
// remembers the old rule can see it was replaced on purpose and not forgotten.
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
    // macOS 27, made EXPLICIT rather than inherited from a neighbour.
    //
    // THIS FLOOR WAS 26 AND WAS RAISED DELIBERATELY — the note is kept in this
    // form, naming what changed, because the old reason is still half true and a
    // reader who remembers it needs to see it was replaced rather than forgotten.
    // What was true: `GmAgentTool.swift` imports FoundationModels
    // UNCONDITIONALLY, and that framework exists only in the macOS 26 SDK or
    // later, so an older SDK does not degrade gracefully — the package does not
    // compile at all. What changed: this package now depends on
    // gmClaudeForFoundationModels, whose own floor is macOS 27 because the
    // server-side `LanguageModel` API it implements (`LanguageModelExecutor`,
    // `LanguageModelExecutorGenerationRequest`, `LanguageModelCapabilities`,
    // `ContextOptions`) ships in the 27 SDK.
    //
    // A DEPENDENCY MAY NOT HAVE A FLOOR ABOVE ITS CONSUMER'S, and this is NOT a
    // thing `@available` can paper over: SwiftPM checks platform floors when it
    // RESOLVES THE GRAPH, strictly before any availability scope exists. Leaving
    // this at 26 does not produce a compile error you could gate — it fails at
    // planning time with "requires minimum platform version 27.0 for the macOS
    // platform, but this target supports 26.0", before a single file is read.
    //
    // Any CI job whose graph transitively includes this package inherits the
    // floor. That is every job in gmk-ci's `packages` matrix and the
    // daemon-release test loop, which is why both moved off macos-26 — see the
    // runner note in `.github/workflows/gmk-ci.yml`, which also records the
    // label surprise (there is no `macos-27`).
    //
    // Spelled as a STRING, not `.macOS(.v27)`: the `.v27` case does not exist
    // in every SwiftPM version that can build this repo, and a manifest that
    // fails to PARSE is a worse failure than one that fails to compile — it
    // takes the whole package graph down with it.
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "GmAgententicsSdk", targets: ["GmAgententicsSdk"]),
    ],
    dependencies: [
        // The first edge. See the header for why it exists and why it cannot
        // cycle.
        .package(path: "../gmDaemonSdk"),
        // The second edge: Anthropic's ClaudeForFoundationModels, VENDORED into
        // `gmk/gmClaudeForFoundationModels` rather than pinned by URL.
        //
        // WHY VENDORED WHEN GRDB IS A REMOTE PIN, since that asymmetry is the
        // first question a reader will have: `unsafeFlags` above bars THIS
        // package from being resolved as a versioned remote dependency, so every
        // package in `gmk/` is consumed by local `path:` — and anything joining
        // that graph has to be reachable the same way. Vendoring is what makes it
        // reachable by path. Provenance, the exact upstream commit, what was left
        // behind, and the re-sync recipe are all in that directory's VENDORED.md.
        //
        // It cannot cycle: the vendored package has ZERO external dependencies,
        // which is also what makes it a self-contained copy rather than the head
        // of a dependency tree.
        .package(path: "../gmClaudeForFoundationModels"),
    ],
    targets: [
        .target(
            name: "GmAgententicsSdk",
            dependencies: [
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(
                    name: "ClaudeForFoundationModels",
                    package: "gmClaudeForFoundationModels"),
            ],
            swiftSettings: [gmAgentOs]
        ),
        // No longer empty. It carries the roster contract — the assertion that
        // every GmAgentTool conformance is reachable from the GmAgentTools
        // namespace — which is VerbRegistryTests' guarantee applied to this
        // surface: a tool that exists but is unreachable fails the build rather
        // than being discovered missing later.
        .testTarget(
            name: "GmAgententicsSdkTests",
            dependencies: [
                "GmAgententicsSdk",
                .product(name: "GmDaemonSdk", package: "gmDaemonSdk"),
                .product(
                    name: "ClaudeForFoundationModels",
                    package: "gmClaudeForFoundationModels"),
            ],
            swiftSettings: [gmAgentOs]
        ),
    ]
)
