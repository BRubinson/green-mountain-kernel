import XCTest
import GmDaemonSdk

/// The multi-call binary's contract, checked against its SOURCE and against the
/// release store that stages it.
///
/// This lives in gmToolchain rather than in `gmk/gmKernel` for the reason every
/// test here lives here: it reads FILES rather than calling symbols. The dispatch
/// itself is top-level code in an executable target's `main.swift`, so it cannot
/// be imported at all — the only alternatives are asserting on the text or
/// building and exec'ing the binary in CI, and the properties that actually cost
/// data if they regress are all visible in the text.
///
/// `gmk/gmKernel` therefore ships NO test target, and its CI row runs
/// `swift build` rather than `swift test`.
final class MultiCallBinaryContractTests: XCTestCase {

    private var dispatchSource: String {
        get throws {
            let url = RepoRoot.package("gmKernel")
                .appendingPathComponent("Sources/gm_kernel/main.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// argv[0] MUST be consulted before argv[1].
    ///
    /// `gm_hook call BACKUP --json '{...}'` arrives with argv[1] == "call". A
    /// subcommand-first dispatcher would try to run `call` as a personality and
    /// break the one client that fires on every tool use. Asserted on ORDER,
    /// because both switches exist and only their sequence is load-bearing.
    func testArgvZeroDispatchPrecedesSubcommandDispatch() throws {
        let text = try dispatchSource
        guard let argv0 = text.range(of: "switch invokedAs {"),
              let sub = text.range(of: "switch rest.first {")
        else {
            return XCTFail("the dispatcher no longer has both switches — read main.swift")
        }
        XCTAssertLessThan(
            argv0.lowerBound, sub.lowerBound,
            """
            the subcommand switch runs BEFORE the argv[0] switch. `gm_hook call \
            BACKUP` has "call" as argv[1], so a subcommand-first rule dispatches \
            `call` as a personality and the hook path stops working.
            """)
    }

    /// A bare invocation must NOT become a writer.
    ///
    /// Of every possible dispatch default this is the one that can cost data: a
    /// typo, a script that lost an argument, or a launchd plist with empty
    /// ProgramArguments must not quietly open the database. The default arm has
    /// to exit non-zero and must not name the headless boot.
    func testBareInvocationExitsWithoutOpeningTheDatabase() throws {
        let text = try dispatchSource
        guard let defaultArm = text.range(of: "    default:\n        FileHandle.standardError")
        else {
            return XCTFail("the bare-invocation arm changed shape — read main.swift")
        }
        let tail = String(text[defaultArm.lowerBound...])
        XCTAssertTrue(tail.contains("exit(2)"), "a bare invocation must exit non-zero")
        XCTAssertFalse(
            tail.contains("bootHeadlessAndRun"),
            "the bare-invocation arm boots the writer — a stray exec would open the db")
    }

    /// There is deliberately no `serve` personality, and the app is not reachable
    /// from the CLI binary. Both halves keep the set of processes that can open
    /// the database as small as the design claims.
    func testNoUndeclaredPersonalities() throws {
        let text = try dispatchSource
        XCTAssertFalse(text.contains("\"serve\""), "an undeclared `serve` personality appeared")
        XCTAssertFalse(
            text.contains("import SwiftUI") || text.contains("import AppKit"),
            "the multi-call CLI linked a UI framework — gm_hook runs on every tool call")
    }

    /// The three entry-point names in the dispatcher and the symlink names the
    /// release store creates MUST be the same set.
    ///
    /// These names are load-bearing rather than cosmetic: `hooks.json`,
    /// `settings.json`, `.mcp.json` and `check_gm_stale.sh` all resolve a binary
    /// by name, and argv[0] is what selects the personality. A staged kernel whose
    /// entry symlinks disagree with its dispatcher is not a degraded install — it
    /// is a hook that cannot launch.
    func testEntryPointNamesMatchTheReleaseStore() throws {
        let text = try dispatchSource
        let store = try String(
            contentsOf: RepoRoot.gmkRoot().appendingPathComponent("scripts/gm_releases.sh"),
            encoding: .utf8)

        for name in ["gm_daemon", "gm_mcp", "gm_hook"] {
            XCTAssertTrue(
                text.contains("case \"\(name)\":"),
                "the dispatcher does not answer to `\(name)`, but the store links it")
            XCTAssertTrue(
                store.contains(name),
                "gm_releases.sh never names `\(name)`, but the dispatcher answers to it")
        }
    }

    /// The dispatcher links all three personalities. A missing product is a
    /// personality that silently stops existing.
    func testManifestLinksEveryPersonality() throws {
        let manifest = try String(
            contentsOf: RepoRoot.package("gmKernel").appendingPathComponent("Package.swift"),
            encoding: .utf8)
        for product in ["GmKernelHost", "GmMcpServer", "GmHookCli"] {
            XCTAssertTrue(
                manifest.contains(product),
                "gmKernel does not link \(product)")
        }
        // Asserted on DECLARATIONS, not on free text. The first version of this
        // matched the word "SwiftUI" anywhere in the file and failed against the
        // manifest's own comment explaining that it links no SwiftUI — a check
        // that cannot tell prose from a dependency is a check that will be
        // "fixed" by deleting the comment.
        XCTAssertFalse(
            manifest.contains(#".product(name: "GmUxComponentLibrary""#),
            "the CLI package linked the UI component library")
        XCTAssertFalse(
            manifest.contains(#".package(path: "../gmUxComponentLibrary")"#)
                || manifest.contains(#".package(path: "../gmVibes")"#),
            "the CLI package took a UI package dependency — gm_hook runs on every tool call")
    }

    /// `gmk/gmKernel` ships no test target, and that is a decision. Recorded here
    /// so the CI matrix's `swift build` row for it reads as intentional rather
    /// than as a row someone forgot to convert to `swift test`.
    func testKernelPackageShipsNoTestTarget() throws {
        let manifest = try String(
            contentsOf: RepoRoot.package("gmKernel").appendingPathComponent("Package.swift"),
            encoding: .utf8)
        XCTAssertFalse(
            manifest.contains(".testTarget"),
            """
            gmKernel gained a test target. That is fine — but its CI row runs \
            `swift build`, so update .github/workflows/gmk-ci.yml in the same \
            change or the tests will never run.
            """)
    }
}
