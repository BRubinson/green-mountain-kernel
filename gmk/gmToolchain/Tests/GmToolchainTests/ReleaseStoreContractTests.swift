import XCTest

/// THE RELEASE STORE CONTRACT, as a build failure.
///
/// Three scripts and one vendored library implement how binaries get onto disk:
///
///   gmk/scripts/rebuild_local.sh     build the working tree, stage `<v>-BETA`
///   gmk/scripts/publish_release.sh   verify, tag, upload, promote
///   gmk/scripts/gm_releases.sh       the store: staging, activation, rollback
///   plugins/gmcc/scripts/install_gm.sh   fetch the newest release (plugin-side)
///
/// The split is load-bearing and this file is what keeps it from eroding. The
/// two things most likely to be "tidied" back into a broken state are the
/// vendored copy of the library and the repo-side-only placement of the publish
/// path — both are asserted here with the reason attached.
final class ReleaseStoreContractTests: XCTestCase {

    private var gmkScripts: URL {
        RepoRoot.gmkRoot().appendingPathComponent("scripts", isDirectory: true)
    }
    private var pluginScripts: URL {
        RepoRoot.pluginRoot().appendingPathComponent("scripts", isDirectory: true)
    }

    // MARK: - The vendored library

    /// `gm_releases.sh` EXISTS TWICE AND THE COPIES MUST BE IDENTICAL.
    ///
    /// Not duplication for its own sake — a measured constraint. A marketplace
    /// install materialises `plugins/gmcc/` ALONE: no `gmk/` beside it, no git
    /// metadata of its own. The plugin's installer therefore cannot source a
    /// library that lives in `gmk/scripts/`, because on a user's machine that
    /// path does not exist.
    ///
    /// Two ways to have gone wrong instead, both rejected:
    ///   - Reimplementing the store logic separately in the installer. Then the
    ///     activation contract has two authors and the symlink layout drifts,
    ///     which presents as an install that half-works.
    ///   - Having the installer climb out of the plugin cache to find `gmk/`.
    ///     That climb is not merely unreliable, it is CONFIDENTLY WRONG: on a
    ///     machine whose `$HOME` is a git repository, `git rev-parse
    ///     --show-toplevel` from the cache returns the home directory.
    ///
    /// So: one authored file, one copy, and this test. `gmk/scripts/` is the
    /// author; if this fails, copy it to the plugin rather than editing both.
    func testVendoredReleaseLibraryIsIdenticalToTheAuthoredOne() throws {
        let authored = gmkScripts.appendingPathComponent("gm_releases.sh")
        let vendored = pluginScripts.appendingPathComponent("gm_releases.sh")
        let a = try String(contentsOf: authored, encoding: .utf8)
        let b = try String(contentsOf: vendored, encoding: .utf8)
        XCTAssertEqual(a, b, """
            plugins/gmcc/scripts/gm_releases.sh has drifted from the authored \
            copy at gmk/scripts/gm_releases.sh. gmk/ is the author — fix by \
            copying, not by editing both:

                cp gmk/scripts/gm_releases.sh plugins/gmcc/scripts/gm_releases.sh
            """)
    }

    // MARK: - What ships in the plugin, and what must not

    /// The publish path is REPO-SIDE ONLY, and that is the primary access
    /// control on it. `source: ./plugins/gmcc` is what the marketplace
    /// distributes, so a publish script placed there would be handed to every
    /// person who installs the plugin. The `gh` push-access check inside the
    /// script is the second line, not the first.
    func testPublishPathIsNotDistributedWithThePlugin() throws {
        let fm = FileManager.default
        for forbidden in ["publish_release.sh", "rebuild_local.sh"] {
            XCTAssertFalse(
                fm.fileExists(atPath: pluginScripts.appendingPathComponent(forbidden).path),
                """
                plugins/gmcc/scripts/\(forbidden) exists. The plugin payload is \
                distributed to everyone who installs it; the build and publish \
                paths belong in gmk/scripts/, which is not part of that payload.
                """)
            XCTAssertTrue(
                fm.fileExists(atPath: gmkScripts.appendingPathComponent(forbidden).path),
                "gmk/scripts/\(forbidden) is missing — the release loop has no \(forbidden)")
        }
    }

    /// The installer ships WITH the plugin, because the person who needs it is
    /// the person who has only the plugin.
    func testInstallerShipsWithThePlugin() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: pluginScripts.appendingPathComponent("install_gm.sh").path),
            """
            plugins/gmcc/scripts/install_gm.sh is missing. A marketplace install \
            has no repo and no sources; without this script it has no way to get \
            binaries at all.
            """)
    }

    /// THE PLUGIN CARRIES NO RUNTIME VERSION PIN.
    ///
    /// `gmk/VERSION` is the runtime version. A second copy inside the plugin
    /// would be a number to bump on every release that could silently disagree
    /// with it — so the installer asks GitHub for the newest `daemon-v*` release
    /// instead, and cannot drift from what was actually published.
    ///
    /// `plugins/gmcc/.claude-plugin/plugin.json` carries the PLUGIN's own
    /// version, which is a different thing and is deliberately decoupled.
    func testPluginCarriesNoRuntimeVersionPin() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: RepoRoot.pluginRoot().appendingPathComponent("VERSION").path),
            """
            plugins/gmcc/VERSION exists. The runtime version lives in gmk/VERSION \
            alone; a plugin-side copy is a second number to bump and a new way for \
            the installer to ask for a version that was never published.
            """)
    }

    // MARK: - The store's own invariants, asserted against the script text

    /// The activation must replace `releases/active` ATOMICALLY, via a temp
    /// name and `mv -f`.
    ///
    /// This is not a style point. `ln -sf target existing_symlink_to_a_dir` does
    /// NOT replace the link — it creates a new link INSIDE the directory the
    /// existing link points at, leaving `active` untouched and burying a stray
    /// symlink in a version directory. It is one of the great unforced errors in
    /// shell installers and it fails silently, so the shape is pinned here.
    func testActivationReplacesTheActiveLinkAtomically() throws {
        let text = try String(
            contentsOf: gmkScripts.appendingPathComponent("gm_releases.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("mv -f"), """
            gm_activate no longer replaces the active symlink with `mv -f`. A bare \
            `ln -sf` onto an existing symlink-to-a-directory does not replace it.
            """)
        XCTAssertTrue(text.contains("ln -sfn"), """
            gm_activate must use `ln -sfn`; without -n the link is followed into \
            the directory it already points at.
            """)
    }

    /// The per-binary links are RELATIVE. A sandbox is a full copy of the
    /// runtime tree at a different path, so absolute symlinks would all point
    /// back at prod — the exact failure the sandbox exists to prevent.
    func testActivationLinksAreRelative() throws {
        let text = try String(
            contentsOf: gmkScripts.appendingPathComponent("gm_releases.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains(#"ln -sfn "releases/active/$b""#), """
            the per-binary links in bin/ are no longer relative. A sandbox copies \
            the whole runtime tree; absolute links would resolve back to prod.
            """)
    }

    /// A local build is ALWAYS stamped `-BETA`, with no flag to suppress it.
    /// That suffix is the only thing distinguishing bits that were merely built
    /// from bits that were published.
    func testLocalBuildsAreAlwaysStampedBeta() throws {
        let text = try String(
            contentsOf: gmkScripts.appendingPathComponent("rebuild_local.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains(#"STAGE_VERSION="$VERSION-BETA""#), """
            rebuild_local.sh no longer stamps -BETA unconditionally. Without it a \
            machine running uncommitted work is indistinguishable from one running \
            the published build.
            """)
    }

    /// Publish verifies the slices with `lipo`, reading the BYTES, rather than
    /// trusting the manifest it wrote itself. This is what catches a `--fast`
    /// (arm64-only) build before it is uploaded as "universal".
    func testPublishVerifiesSlicesFromTheBinariesNotTheManifest() throws {
        let text = try String(
            contentsOf: gmkScripts.appendingPathComponent("publish_release.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("lipo -archs"), """
            publish_release.sh no longer reads architectures with lipo. A manifest \
            records what a build INTENDED; only the binary knows what it IS.
            """)
        XCTAssertTrue(text.contains("permissions.push"), """
            publish_release.sh no longer checks push access before tagging. Without \
            it a non-owner gets an opaque 403 partway through a publish.
            """)
    }

    /// The MCP launcher NEVER builds or installs. It used to build inline,
    /// which put a cold release build on the connect path: the session spent
    /// its handshake budget in bash and then ran with no pen, which is
    /// indistinguishable from the server not being registered.
    func testMcpLauncherNeverBuildsOrInstalls() throws {
        let text = try String(
            contentsOf: pluginScripts.appendingPathComponent("run_mcp.sh"), encoding: .utf8)
        // COMMENTS ARE STRIPPED FIRST, and that is not a detail: the script's
        // header explains at length WHY it must never run `swift build`, so a
        // naive substring search fails on the very comment that documents the
        // invariant — punishing the explanation instead of the violation.
        let code = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        // Only the BUILD is banned, not every mention of the installers. The
        // script's failure message names install_gm.sh on purpose — telling the
        // user how to fix it is the job; running it for them is the bug.
        XCTAssertFalse(code.contains("swift build"), """
            run_mcp.sh runs `swift build`. Getting binaries onto disk is an \
            explicit act; a build on the MCP connect path costs the session its \
            pen — it spends the handshake budget in bash and then builds its \
            first prompt with no pen in it.
            """)
        XCTAssertTrue(text.contains("exit 1"), """
            run_mcp.sh must exit NON-ZERO when gm_mcp is missing, so Claude Code \
            surfaces a named connection failure instead of a server that stays up \
            and fails every tool call.
            """)
    }
}
