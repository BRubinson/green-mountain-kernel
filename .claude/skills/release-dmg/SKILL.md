---
name: release-dmg
description: Build the gm_kernel macOS app (the GM Vibes UI — gmk/Sources/UX/Apps/Vibes, sources and bundle payload together in this monorepo) into a DMG, and either hand it over as a local build or ship it as the unified gm_kernel release, which carries the CLI inside the bundle. Use when the user wants to cut a release, ship a new DMG, upload a build to GitHub, or distribute the app.
---

# release-dmg

## The app no longer has a release of its own

**There is ONE release, ONE artifact.** `gm_kernel-v<version>` carries the DMG
and its checksum at a single version taken from `gmk/VERSION`. The CLI
(`gm_daemon`, `gm_mcp`, `gm_hook`) is the bundle's own executable,
`Contents/MacOS/gm_kernel`; the installer extracts it:

```
gm_kernel-v54.0.2
├── gm_kernel-54.0.2.dmg
└── gm_kernel-54.0.2.dmg.sha256
```

This replaced a separate `gmvibes-v<MARKETING_VERSION>` track, and later a
tarball beside the DMG. `gmk/scripts/release.sh` is retired and exits 2 with a
pointer — **do not call it**, and do not reimplement what it did. The app's
`MARKETING_VERSION` is not edited by hand either: `build-dmg.sh` stamps it from
`gmk/VERSION` at archive time. The Xcode target is `gm_kernel`, the schemes are
`gm_kernel` (Debug) and `gm_kernel_beta` (Beta), and the bundle is
`gm_kernel.app`.

So decide which of these the user is actually asking for.

## A. Publish a release (the app AND the binaries)

This is what "cut a release" means now. It is the repo-side path and it requires
push access:

```sh
bash gmk/scripts/rebuild_local.sh --app    # xcodebuild → signed bundle, staged <version>-BETA
bash gmk/scripts/publish_release.sh        # verify, test, notarize, tag, upload
```

`publish_release.sh` PROMOTES the staged signed bundle; it does not build one,
and it refuses when there is none. Things worth surfacing to the user BEFORE
running it:

- **The working tree must be clean** and `gmk/VERSION` must not already be
  tagged. Bump `gmk/VERSION` and commit first.
- **The staged bundle must come from HEAD.** If it doesn't, re-run
  `rebuild_local.sh --app`; publish compares the staged manifest's sha against
  HEAD.
- **A Developer ID is required by default.** Without one it dies rather than
  publishing an ad-hoc DMG that Gatekeeper blocks on every machine but this one.
  `--allow-adhoc` overrides, for a private or test release only — tell the user
  that is what they are getting.
- **The baked root must be `~/gmfs`.** A Beta or Debug bundle is refused: it
  would install to `/Applications` as production and point at the wrong
  database on every machine that upgrades.
- Use `--dry-run` to run every check without tagging, pushing or uploading
  anything. Prefer this first when unsure.

Allow a generous timeout: the build, the test suite (`xcodebuild test` against
the staged kernel) and notarization take several minutes.

## B. Just build a DMG, publishing nothing

For a one-off build to hand to somebody, or to check the app archives:

```sh
bash gmk/scripts/build-dmg.sh          # → gmk/build/gm_kernel-<gmk/VERSION>.dmg
bash gmk/scripts/build-dmg.sh 1.2.3    # → gmk/build/gm_kernel-1.2.3.dmg
NOTARIZE=1 bash gmk/scripts/build-dmg.sh
```

It archives through the WORKSPACE (`gmk/gmk.xcworkspace`, scheme `gm_kernel`),
so package resolution uses the one committed lockfile. Signing auto-detects: a
*Developer ID Application* certificate means a hardened-runtime signed app,
otherwise ad-hoc. Say which one happened — don't let a user who asked for a
distributable build walk away with an ad-hoc DMG.

## C. Install the published app on this machine

The plugin's installer upgrades the app and extracts the binaries from it:

```sh
bash plugins/gmcc/scripts/install_gm.sh          # binaries + app
bash plugins/gmcc/scripts/install_gm.sh --app    # the app only
bash plugins/gmcc/scripts/install_gm.sh --check  # report, install nothing
```

It stages the DMG under `$GM_FS_ROOT/apps/downloads/<version>/`, verifies the
SHA-256 sidecar, and installs to `/Applications` (`GM_APP_DEST` overrides).
**It refuses while the app is running** — replacing a live bundle corrupts it —
so quit the app first.

## Preflight

```sh
gh auth status                                  # must be logged in
git remote get-url origin                       # must point at green-mountain-kernel
security find-identity -v -p codesigning | grep "Developer ID Application" || true
cat gmk/VERSION
```

If `gh` is not authenticated, stop and tell the user to run
`! gh auth login -h github.com -s repo -w`.

## Report

Print the release URL (`gh release view <tag> --json url -q .url`) and state
plainly which signing path was taken.

## Notarization setup (one-time)

Notarization needs a `notarytool` keychain profile named `gmcc-ui` (historical
name, kept so existing stored credentials keep working):

```sh
xcrun notarytool store-credentials gmcc-ui \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
```

A Developer ID Application certificate requires enrollment in the Apple Developer
Program. Without it, builds are ad-hoc and recipients clear quarantine once:
`xattr -dr com.apple.quarantine /Applications/gm_kernel.app`.
