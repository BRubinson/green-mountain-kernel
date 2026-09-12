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

    /// The activation must replace `releases/active` atomically AND without
    /// following it: `ln -sfn` to build the temp link, `mv -fh` to install it.
    ///
    /// THIS TEST EXISTS BECAUSE THE BUG SHIPPED. `active` is a symlink to a
    /// DIRECTORY, and both obvious spellings silently do something else:
    /// `ln -sf new active` creates `active/new`, and `mv -f tmp active` moves
    /// `tmp` INTO the directory. The first version of `gm_activate` used
    /// `mv -f`, promoted a release, wrote the new version into `.gm_version` —
    /// and left `active` pointing at the old directory with a stray
    /// `.active.tmp.<pid>` buried inside it. The store claimed one version and
    /// executed another, with no error anywhere.
    ///
    /// `-n` (ln) and `-h` (mv) both mean "operate on the link, don't follow it".
    /// A regression here is invisible in normal use, so it is pinned in text.
    func testActivationReplacesTheActiveLinkWithoutFollowingIt() throws {
        let text = try String(
            contentsOf: gmkScripts.appendingPathComponent("gm_releases.sh"), encoding: .utf8)
        XCTAssertTrue(text.contains("mv -fh"), """
            gm_activate does not use `mv -fh`. Without -h, mv FOLLOWS the `active` \
            symlink and moves the temp link INTO the directory it points at, \
            leaving the old version active while .gm_version records the new one.
            """)
        XCTAssertFalse(text.contains("mv -f \""), """
            gm_activate still has a bare `mv -f` on a symlink target. Use `mv -fh`.
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

    // MARK: - One release, one version

    /// THE TAG NAMESPACE HAS EXACTLY ONE AUTHOR: `GM_TAG_PREFIX` in the shared
    /// library. The publisher and the installer must not each carry their own
    /// spelling of it.
    ///
    /// This is the failure the unified release was built to make impossible. The
    /// two sides previously hardcoded `daemon-v` independently, so the publisher
    /// and the installer agreed only by coincidence — and when the app was added
    /// on its own `gmvibes-v*` tag, a third spelling appeared in a third script
    /// that neither of the other two knew about. A literal tag prefix in either
    /// script is that drift starting again.
    func testTagPrefixIsDefinedOnceInTheSharedLibrary() throws {
        let library = try String(
            contentsOf: gmkScripts.appendingPathComponent("gm_releases.sh"), encoding: .utf8)
        XCTAssertTrue(library.contains(#"GM_TAG_PREFIX="gm_kernel-v""#), """
            gm_releases.sh no longer defines GM_TAG_PREFIX="gm_kernel-v". It is \
            the single authority for the release namespace; both the publisher \
            and the installer derive their tag from it.
            """)

        for script in [
            gmkScripts.appendingPathComponent("publish_release.sh"),
            pluginScripts.appendingPathComponent("install_gm.sh"),
        ] {
            let code = uncommented(try String(contentsOf: script, encoding: .utf8))
            XCTAssertTrue(code.contains("GM_TAG_PREFIX"), """
                \(script.lastPathComponent) does not use GM_TAG_PREFIX. The tag \
                namespace must come from gm_releases.sh, not be spelled again here.
                """)
            XCTAssertFalse(code.contains(#"TAG="gm_kernel-v"#), """
                \(script.lastPathComponent) hardcodes the tag prefix instead of \
                using GM_TAG_PREFIX. Two spellings of one namespace is how the \
                publisher and the installer drift apart; the symptom is a 404 \
                that reads like a network problem.
                """)
        }
    }

    /// THE RELEASE CARRIES THE APP. A release with only binaries can upgrade
    /// half a system: the user gets a new daemon and keeps whatever GMVibes they
    /// had, with no record of which app went with which runtime.
    func testPublishUploadsTheAppAlongsideTheBinaries() throws {
        let code = uncommented(try String(
            contentsOf: gmkScripts.appendingPathComponent("publish_release.sh"), encoding: .utf8))
        XCTAssertTrue(code.contains("DMG_ASSET"), """
            publish_release.sh no longer builds or uploads a DMG. The unified \
            release exists so one tag carries the binaries AND the app at one \
            version.
            """)
        XCTAssertTrue(code.contains("build-dmg.sh"), """
            publish_release.sh no longer invokes build-dmg.sh. The app has no \
            staging step of its own, so publish is where it gets built.
            """)
    }

    /// NOTARIZATION IS A GATE, NOT A WARNING. An ad-hoc DMG runs only on the
    /// machine that built it; Gatekeeper refuses it everywhere else with
    /// "GMVibes is damaged", which is neither true nor actionable. The retired
    /// `release.sh` would publish one with a note telling recipients to strip
    /// quarantine by hand.
    func testPublishRefusesAnUnsignedAppUnlessAsked() throws {
        let code = uncommented(try String(
            contentsOf: gmkScripts.appendingPathComponent("publish_release.sh"), encoding: .utf8))
        XCTAssertTrue(code.contains("--allow-adhoc"), """
            publish_release.sh no longer has an --allow-adhoc escape hatch, which \
            means it either refuses always or refuses never. Both are wrong: a \
            private test release is real, and it has to be asked for.
            """)
        XCTAssertTrue(code.contains("Developer ID Application"), """
            publish_release.sh no longer checks for a Developer ID before \
            building the DMG. Without that check an ad-hoc build ships silently \
            and is Gatekeeper-blocked for every recipient.
            """)
    }

    /// The app version is STAMPED from `gmk/VERSION`, never read out of the
    /// project file. One release, one number — and a build that rewrote
    /// project.pbxproj would dirty the tree publish requires to be clean.
    func testTheAppVersionIsStampedFromTheVersionPin() throws {
        let code = uncommented(try String(
            contentsOf: gmkScripts.appendingPathComponent("build-dmg.sh"), encoding: .utf8))
        XCTAssertTrue(code.contains(#"MARKETING_VERSION="$VERSION""#), """
            build-dmg.sh no longer overrides MARKETING_VERSION from gmk/VERSION. \
            Without the stamp the app carries a hand-edited version that can \
            disagree with the tag it ships under.
            """)
        XCTAssertFalse(code.contains("project.pbxproj"), """
            build-dmg.sh reads the version out of project.pbxproj again. \
            gmk/VERSION is the pin for the binaries AND the app; reading the \
            project file reintroduces the second number the unified release removed.
            """)
    }

    /// `release.sh` is RETIRED and must stay that way. It published the app on
    /// its own tag with its own version — the exact split the unified release
    /// removed. It is kept as a signpost, so it has to keep refusing.
    func testTheAppOnlyReleasePathStaysRetired() throws {
        let path = gmkScripts.appendingPathComponent("release.sh")
        let text = try String(contentsOf: path, encoding: .utf8)
        let code = uncommented(text)
        XCTAssertFalse(code.contains("gh release create"), """
            gmk/scripts/release.sh creates a GitHub release again. The app is \
            published by publish_release.sh inside the unified gm_kernel-v* \
            release; a second publisher means two tags and two version numbers \
            with no recorded relationship.
            """)
        XCTAssertTrue(code.contains("exit 2"), """
            gmk/scripts/release.sh no longer refuses. It is a signpost kept so \
            that calling it explains where the capability went rather than \
            failing with "command not found".
            """)
    }

    /// Strips comment lines so a substring search tests the CODE, not the
    /// explanation above it. Several headers in these scripts necessarily name
    /// the thing they forbid.
    private func uncommented(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
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
