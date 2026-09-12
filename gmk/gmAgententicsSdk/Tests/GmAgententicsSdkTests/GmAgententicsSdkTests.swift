// GmAgententicsSdkTests — the smoke test that proves the target is wired to the
// right module.
//
// THE "EMPTY BY DESIGN" NOTE THIS HEADER USED TO CARRY IS RETIRED. It said the
// target deliberately held no assertions, because the package itself
// deliberately held almost no code. The package has since been filled in, and
// the real assertions now live next door in GmAgentToolRosterTests. What is left
// here is the one thing that file cannot check for itself — see below.
//
// WHY THE FILE EXISTS AT ALL, rather than the target being deleted: a
// `.testTarget` whose `Tests/<name>/` directory is absent does not merely run
// zero tests — SwiftPM cannot locate the target's sources, falls back to
// scanning, resolves onto `Sources/GmAgententicsSdk/`, and fails the WHOLE
// package with "target 'GmAgententicsSdkTests' has overlapping sources". That
// error is a resolution failure, so it takes down `swift build` too, not just
// `swift test` — and it takes down any workspace that includes this package,
// because a workspace resolves every member as one graph.
//
// The single smoke test is the smallest thing that proves the target is wired
// to the right module: if the import ever stops resolving, this fails loudly
// rather than silently reporting a green run of zero tests.

import XCTest
import GmAgententicsSdk

final class GmAgententicsSdkSmokeTests: XCTestCase {
    /// Asserts only that the module links and imports. See the header for why
    /// this file stays at exactly this size.
    func testModuleImports() {
        XCTAssertTrue(true)
    }
}
