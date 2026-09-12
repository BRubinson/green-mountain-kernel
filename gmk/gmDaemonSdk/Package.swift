// swift-tools-version:6.0

// gmDaemonSdk — the BASE layer of the gmk graph.
//
// This is "the SDK plus the shared domain layer", and saying so is the point:
// it is not only the wire types and the client. It holds `Protocol/`, `Client/`,
// `Dope/`, `Diagram/` models, `Hook/`, `Kbite/`, `Environment/`, `Paths`,
// `GitHead`, `StructuredPatch` and `StoreError` — roughly 15k loc.
//
// WHY THE DOMAIN LAYER LIVES HERE rather than in a seventh module: the wire
// types already reference the document types. `Protocol/Messages.swift` names
// `DopeTree` six times, `DopeDocument` and `DopeOverlay` twice each, and
// `DiagramTree` three times. Wire types cannot sit ABOVE document types, so any
// layering that puts the Dope/Diagram models above this package is a dependency
// cycle. That constraint decided the shape; it was not a preference.
//
// `StoreError` was the single upward dependency in the old monolith and moved
// DOWN into this target — see its own header. Without that move nothing here
// compiles.
//
// Products:
//   - GmDaemonSdk (library)    every other module depends on this one
//   - gm_hook     (executable) the shell-callable client and raw-wire passthrough
//
// gm_hook ships FROM HERE rather than from a package of its own. It is a socket
// client and never reaches persistence, so it links the SDK alone — a seventh
// package for one executable would buy nothing but a seventh manifest.

import PackageDescription

let package = Package(
    name: "gmDaemonSdk",
    // macOS 14 is the Observation floor the @Observable-friendly DaemonClient
    // needs. It is DELIBERATELY well below the app's deployment target: a base
    // library must not inherit one consumer's floor.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GmDaemonSdk", targets: ["GmDaemonSdk"]),
        .executable(name: "gm_hook", targets: ["gm_hook"]),
    ],
    // ZERO EXTERNAL DEPENDENCIES, and that is the load-bearing property of this
    // manifest rather than an accident of what it happens to need. GRDB is
    // named by exactly one manifest (gmDaemon); because nothing here pulls it,
    // it stays out of the link closure of every consumer that does not persist
    // — the app included. An added dependency here is added everywhere, so
    // adding one is a graph decision, not a convenience.
    dependencies: [],
    targets: [
        .target(name: "GmDaemonSdk"),
        // NO ArgumentParser. That dependency earns its place for a large
        // declarative command tree; this is a dozen ops verbs plus a raw
        // passthrough, and it parses argv by hand.
        .executableTarget(
            name: "gm_hook",
            dependencies: ["GmDaemonSdk"]
        ),
        // Fixtures/ holds wire_keys.golden — the frozen snake_case wire
        // contract, regenerated and diffed by scripts/wire_keys.py. It lives
        // in THIS package because the wire types do; it was previously filed
        // with the persistence tests, where a change to the Protocol types
        // would not have been next to the golden that freezes them.
        .testTarget(
            name: "GmDaemonSdkTests",
            dependencies: ["GmDaemonSdk"],
            exclude: ["Fixtures"]
        ),
    ]
)
